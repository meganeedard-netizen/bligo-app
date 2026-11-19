-- Retours du RDV Landerneau (19/11/2026)
-- 1. Public visé (moins de 12 ans, 12-16 ans, plus de 16 ans), âge minimum
--    et signalétique (PEGI pour les jeux vidéo, -10/-12/-16/-18 pour les
--    films), plateforme des jeux vidéo ; date de naissance de l'usager.
-- 2. Prêt/retour/recherche au comptoir en scannant l'ISBN quand la
--    médiathèque ne colle pas de code-barres sur ses documents.
-- 3. Réglage « réservation des seuls documents empruntés » (le reste se
--    prend en rayon, prêt aux automates).
-- 4. Paniers de catalogage par agent (brouillons gardés en base, par lot).
-- 5. Ressources numériques : déjà en place depuis le 09/10/2026.

-- ============ 1. Âges ============
alter table public.books add column if not exists audience text;
alter table public.books add column if not exists min_age integer;
alter table public.books add column if not exists age_rating text;
alter table public.books add column if not exists platform text;
do $$ begin
  alter table public.books add constraint books_audience_check
    check (audience is null or audience in ('moins_12', '12_16', 'plus_16'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.books add constraint books_min_age_check
    check (min_age is null or min_age between 0 and 18);
exception when duplicate_object then null; end $$;

-- « Réservé aux adultes » existant = âge minimum 18 ans.
update public.books set min_age = 18 where adult_only and min_age is null;

alter table public.profiles add column if not exists birth_date date;

-- Message de refus si l'usager n'a pas l'âge du document, sinon null.
-- Âge inconnu (pas de date de naissance) : un compte mineur est bloqué à
-- partir de 16 ans minimum, comme l'était déjà « réservé aux adultes ».
create or replace function public.age_block_message(p_user uuid, p_book bigint)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_min integer; v_rating text; v_birth date; v_tariff text; v_age integer;
begin
  select min_age, age_rating into v_min, v_rating from public.books where id = p_book;
  if coalesce(v_min, 0) = 0 then return null; end if;
  select birth_date, tariff_category into v_birth, v_tariff from public.profiles where id = p_user;
  if v_birth is not null then
    v_age := extract(year from age(current_date, v_birth))::int;
    if v_age < v_min then
      return 'Ce document est réservé aux ' || v_min || ' ans et plus' || coalesce(' (' || v_rating || ')', '') || '.';
    end if;
    return null;
  end if;
  if v_tariff = 'mineur' and v_min >= 16 then
    return 'Ce document est réservé aux ' || v_min || ' ans et plus' || coalesce(' (' || v_rating || ')', '') || '. Renseigne la date de naissance de l''usager pour vérifier son âge.';
  end if;
  return null;
end $$;

-- ============ 3. Réservation des seuls documents empruntés ============
alter table public.communes add column if not exists reservation_scope text not null default 'tous';
do $$ begin
  alter table public.communes add constraint communes_reservation_scope_check
    check (reservation_scope in ('tous', 'empruntes'));
exception when duplicate_object then null; end $$;

create or replace function public.set_reservation_scope(p_scope text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_direction() or public.is_super_admin()) then
    raise exception 'Réglage réservé à la direction';
  end if;
  if p_scope not in ('tous', 'empruntes') then raise exception 'Valeur invalide'; end if;
  update public.communes set reservation_scope = p_scope where id = public.agent_commune_id();
end $$;
grant execute on function public.set_reservation_scope(text) to authenticated;

-- Contrôles ajoutés au déclencheur des réservations (âge + documents en rayon).
do $$
declare d text; anchor text := E'  if v_tariff_category = ''mineur'' and v_adult_only then';
begin
  d := pg_get_functiondef('public.enforce_reservation_limits'::regproc);
  if position('age_block_message' in d) = 0 then
    if position(anchor in d) = 0 then raise exception 'enforce_reservation_limits : repère introuvable'; end if;
    d := replace(d, anchor,
E'  if tg_table_name = ''reservations'' then\n'
'    v_limit_error := public.age_block_message(new.user_id, new.book_id);\n'
'    if v_limit_error is not null then raise exception ''%'', v_limit_error; end if;\n'
'    -- Médiathèque où seuls les documents déjà empruntés se réservent : ce\n'
'    -- qui est en rayon se prend sur place (demande de l''usager lui-même ;\n'
'    -- les agents gardent la main).\n'
'    if auth.uid() = new.user_id and exists (\n'
'      select 1 from public.books b join public.communes c on c.id = b.commune_id\n'
'      where b.id = new.book_id and c.reservation_scope = ''empruntes'' and b.available\n'
'    ) then\n'
'      raise exception ''Ce document est disponible en rayon : viens le prendre directement à la médiathèque.'';\n'
'    end if;\n'
'    v_limit_error := null;\n'
'  end if;\n\n' || anchor);
    execute d;
  end if;
end $$;

-- Même contrôle d'âge au prêt au comptoir.
do $$
declare d text; anchor text := E'    return jsonb_build_object(''ok'', false, ''message'', ''Ce livre est réservé aux comptes majeurs.'');\n  end if;';
begin
  d := pg_get_functiondef('public.scan_checkout'::regproc);
  if position('age_block_message' in d) = 0 then
    if position(anchor in d) = 0 then raise exception 'scan_checkout : repère introuvable'; end if;
    d := replace(d, anchor, anchor ||
E'\n\n  if public.age_block_message(v_user_id, v_book.id) is not null then\n'
'    return jsonb_build_object(''ok'', false, ''message'', public.age_block_message(v_user_id, v_book.id));\n'
'  end if;');
    execute d;
  end if;
end $$;

-- ============ 2. Scan par ISBN ============
-- Code scanné → code-barres de l'exemplaire. Code-barres exact d'abord ;
-- sinon ISBN/EAN du document : l'exemplaire de la médiathèque de l'agent,
-- disponible pour un prêt, emprunté pour un retour.
create or replace function public.resolve_copy_code(p_code text, p_purpose text default 'checkout')
returns text language sql stable security definer set search_path = public as $$
  with s as (select trim(p_code) as code, regexp_replace(upper(trim(p_code)), '[^0-9X]', '', 'g') as d)
  select coalesce(
    (select bc.barcode from public.book_copies bc, s where bc.barcode = s.code),
    (select bc.barcode
       from public.book_copies bc join public.books b on b.id = bc.book_id, s
      where length(s.d) in (10, 13)
        and regexp_replace(upper(coalesce(b.isbn, '')), '[^0-9X]', '', 'g') = s.d
        and bc.status not in ('withdrawn', 'lost')
      order by (bc.current_commune_id = public.agent_commune_id()) desc,
               case p_purpose
                 when 'return' then case bc.status when 'borrowed' then 0 else 1 end
                 else case bc.status when 'available' then 0 when 'reserved' then 1 else 2 end
               end,
               bc.id
      limit 1),
    (select code from s));
$$;

do $$
declare
  f text; purpose text; d text;
begin
  foreach f in array array['scan_checkout', 'scan_return', 'counter_checkout', 'scan_lookup'] loop
    purpose := case f when 'scan_return' then 'return' when 'scan_lookup' then 'lookup' else 'checkout' end;
    d := pg_get_functiondef(('public.' || f)::regproc);
    if position('resolve_copy_code' in d) > 0 then continue; end if;
    if position('barcode = trim(p_barcode)' in d) = 0 then raise exception '% : repère introuvable', f; end if;
    d := replace(d, 'barcode = trim(p_barcode)', 'barcode = public.resolve_copy_code(p_barcode, ''' || purpose || ''')');
    execute d;
  end loop;
end $$;

-- ============ 4. Paniers de catalogage ============
create table if not exists public.catalog_drafts (
  id bigserial primary key,
  commune_id bigint not null references public.communes(id) on delete cascade,
  agent_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  local_id text not null,
  lot text,
  verified boolean not null default false,
  data jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (agent_id, local_id)
);
alter table public.catalog_drafts enable row level security;
drop policy if exists "Les agents gèrent les brouillons de leur médiathèque" on public.catalog_drafts;
create policy "Les agents gèrent les brouillons de leur médiathèque" on public.catalog_drafts
  for all using (public.is_super_admin() or (public.is_agent() and commune_id = public.agent_commune_id()))
  with check (public.is_super_admin() or (public.is_agent() and commune_id = public.agent_commune_id()));

-- Reprendre le lot d'un collègue (absent, en congé…).
create or replace function public.take_over_catalog_lot(p_agent uuid, p_lot text)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not (public.is_agent() or public.is_super_admin()) then raise exception 'Accès réservé aux agents'; end if;
  -- Un brouillon déjà à moi avec le même identifiant : on garde le mien.
  delete from public.catalog_drafts d where d.agent_id = p_agent and d.lot is not distinct from p_lot
    and exists (select 1 from public.catalog_drafts m where m.agent_id = auth.uid() and m.local_id = d.local_id);
  update public.catalog_drafts set agent_id = auth.uid(), updated_at = now()
   where agent_id = p_agent and lot is not distinct from p_lot and commune_id = public.agent_commune_id();
  get diagnostics n = row_count;
  return n;
end $$;
grant execute on function public.take_over_catalog_lot(uuid, text) to authenticated;

-- Noms des agents qui ont des brouillons (affichage des paniers de l'équipe).
create or replace function public.catalog_baskets()
returns table (agent_id uuid, agent_name text, lot text, total integer, verified integer, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select d.agent_id, p.full_name, d.lot, count(*)::int, count(*) filter (where d.verified)::int, max(d.updated_at)
    from public.catalog_drafts d left join public.profiles p on p.id = d.agent_id
   where (public.is_agent() or public.is_super_admin()) and d.commune_id = public.agent_commune_id()
   group by 1, 2, 3 order by max(d.updated_at) desc;
$$;
grant execute on function public.catalog_baskets() to authenticated;

-- ============ 5. Ressources numériques ============
-- Déjà en place depuis le 09/10/2026 (add_family_and_digital.sql, Réglages >
-- Ressources numériques, affichées dans le profil de l'usager).

-- ============ 6. Type « Jeu vidéo » ============
insert into public.document_types (commune_id, label, kind, sort_order)
select null, 'Jeu vidéo', 'autre', 105
where not exists (select 1 from public.document_types where label = 'Jeu vidéo' and commune_id is null);

-- ============ 7. Date de naissance saisie par l'agent ============
-- Remplit aussi la tranche d'âge du rapport Néoscrib (0-14, 15-64, 65+).
create or replace function public.set_usager_birth_date(p_user_id uuid, p_birth date)
returns text language plpgsql security definer set search_path = public as $$
declare v_age integer; v_group text;
begin
  if not (public.is_super_admin() or (public.is_agent() and exists (
    select 1 from public.profiles p where p.id = p_user_id and p.commune_id = public.agent_commune_id()))) then
    raise exception 'Réservé aux agents de la médiathèque de cet usager';
  end if;
  if p_birth is not null and (p_birth > current_date or p_birth < date '1900-01-01') then
    raise exception 'Date de naissance invalide';
  end if;
  if p_birth is not null then
    v_age := extract(year from age(current_date, p_birth))::int;
    v_group := case when v_age < 15 then 'enfant' when v_age < 65 then 'adulte' else 'senior' end;
  end if;
  update public.profiles set birth_date = p_birth, age_group = coalesce(v_group, age_group) where id = p_user_id;
  return v_group;
end $$;
grant execute on function public.set_usager_birth_date(uuid, date) to authenticated;

-- ============ 8. Tranche d'âge au lieu de la date de naissance (RGPD) ============
-- Mégane (19/11/2026) : la date de naissance n'est pas nécessaire au contrôle
-- (minimisation des données). On garde seulement la tranche : moins de 12 ans,
-- 12-16 ans, plus de 16 ans. Aucune date n'avait été saisie.
alter table public.profiles add column if not exists age_band text;
do $$ begin
  alter table public.profiles add constraint profiles_age_band_check
    check (age_band is null or age_band in ('moins_12', '12_16', 'plus_16'));
exception when duplicate_object then null; end $$;
drop function if exists public.set_usager_birth_date(uuid, date);
alter table public.profiles drop column if exists birth_date;

-- Moins de 12 ans : bloqué à partir de 10 ans minimum (films -10, PEGI 12…).
-- 12-16 ans : bloqué à partir de 16 ans. Plus de 16 ans : bloqué à 18 ans
-- tant que le compte est mineur. Sans tranche : compte mineur bloqué à 16.
create or replace function public.age_block_message(p_user uuid, p_book bigint)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_min integer; v_rating text; v_band text; v_tariff text; v_blocked boolean;
begin
  select coalesce(min_age, case when adult_only then 18 end), age_rating into v_min, v_rating from public.books where id = p_book;
  if coalesce(v_min, 0) = 0 then return null; end if;
  select age_band, tariff_category into v_band, v_tariff from public.profiles where id = p_user;
  v_blocked := case v_band
    when 'moins_12' then v_min >= 10
    when '12_16' then v_min >= 16
    when 'plus_16' then v_min >= 18 and v_tariff = 'mineur'
    else v_tariff = 'mineur' and v_min >= 16
  end;
  if v_blocked then
    return 'Ce document est réservé aux ' || v_min || ' ans et plus' || coalesce(' (' || v_rating || ')', '') || '.';
  end if;
  return null;
end $$;

create or replace function public.set_usager_age_band(p_user_id uuid, p_band text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_super_admin() or (public.is_agent() and exists (
    select 1 from public.profiles p where p.id = p_user_id and p.commune_id = public.agent_commune_id()))) then
    raise exception 'Réservé aux agents de la médiathèque de cet usager';
  end if;
  if p_band is not null and p_band not in ('moins_12', '12_16', 'plus_16') then
    raise exception 'Tranche d''âge inconnue';
  end if;
  update public.profiles set age_band = p_band where id = p_user_id;
end $$;
grant execute on function public.set_usager_age_band(uuid, text) to authenticated;

-- ============ 9. Année de naissance (choix de Mégane, 19/11/2026) ============
-- 3 tranches ne suffisaient pas pour PEGI 3/7 et les films -10. L'année seule
-- (pas la date complète) suffit et l'âge avance tout seul chaque année.
-- Âge retenu = âge le plus bas possible (année en cours - année - 1) : un
-- enfant n'emprunte jamais un document avant d'avoir l'âge. Un compte majeur
-- compte toujours comme 18 ans et plus.
alter table public.profiles add column if not exists birth_year smallint;
do $$ begin
  alter table public.profiles add constraint profiles_birth_year_check
    check (birth_year is null or birth_year between 1900 and 2100);
exception when duplicate_object then null; end $$;
-- Le select de l'appli en ligne lit encore age_band : colonne gardée vide
-- jusqu'au déploiement, supprimée juste après.
drop function if exists public.set_usager_age_band(uuid, text);

create or replace function public.reader_min_age(p_birth_year integer, p_tariff text)
returns integer language sql immutable as $$
  select case
    when p_tariff = 'majeur' then greatest(18, coalesce(extract(year from current_date)::int - p_birth_year - 1, 18))
    when p_birth_year is null then null
    else extract(year from current_date)::int - p_birth_year - 1
  end;
$$;

create or replace function public.age_block_message(p_user uuid, p_book bigint)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_min integer; v_rating text; v_year integer; v_tariff text; v_age integer;
begin
  select coalesce(min_age, case when adult_only then 18 end), age_rating into v_min, v_rating from public.books where id = p_book;
  if coalesce(v_min, 0) = 0 then return null; end if;
  select birth_year, tariff_category into v_year, v_tariff from public.profiles where id = p_user;
  v_age := public.reader_min_age(v_year, v_tariff);
  if (v_age is not null and v_age < v_min) or (v_age is null and v_tariff = 'mineur' and v_min >= 16) then
    return 'Ce document est réservé aux ' || v_min || ' ans et plus' || coalesce(' (' || v_rating || ')', '') || '.';
  end if;
  return null;
end $$;

create or replace function public.set_usager_birth_year(p_user_id uuid, p_year integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_super_admin() or (public.is_agent() and exists (
    select 1 from public.profiles p where p.id = p_user_id and p.commune_id = public.agent_commune_id()))) then
    raise exception 'Réservé aux agents de la médiathèque de cet usager';
  end if;
  if p_year is not null and (p_year < 1900 or p_year > extract(year from current_date)) then
    raise exception 'Année de naissance invalide';
  end if;
  update public.profiles set birth_year = p_year where id = p_user_id;
end $$;
grant execute on function public.set_usager_birth_year(uuid, integer) to authenticated;

-- 10. Colonne des tranches supprimée une fois l'année de naissance en ligne (19/11/2026).
alter table public.profiles drop column if exists age_band;
