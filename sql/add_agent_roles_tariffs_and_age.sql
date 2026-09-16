-- BliGO — Retour de terrain du 14/09/2026, points 9, 11 et 12 (16/09/2026)
-- Rôles agents (direction/agent), catégorie tarifaire usager (mineur/majeur/gratuité)
-- sans date de naissance (choix RGPD de Mégane), livres réservés aux adultes,
-- tarifs par médiathèque éditables uniquement par la direction.
--
-- Migration ADDITIVE, à exécuter après add_commune_settings_and_flagging.sql.
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run


-- ============================================================
-- 1. Rôles agents : direction (accès complet) / agent (restreint)
-- ============================================================
-- Les comptes agents déjà en place gardent 'direction' par défaut, pour ne rien
-- restreindre rétroactivement : c'est un agent avec un compte 'direction' qui
-- décidera ensuite de créer des comptes 'agent' plus limités.

alter table public.profiles
  add column if not exists agent_level text check (agent_level in ('agent', 'direction'));

update public.profiles set agent_level = 'direction' where role = 'agent' and agent_level is null;

comment on column public.profiles.agent_level is 'Sous-niveau du rôle agent : direction (accès complet) ou agent (restreint). Non pertinent pour les rôles usager/super_admin.';

create or replace function public.is_direction()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and (role = 'super_admin' or (role = 'agent' and agent_level = 'direction'))
  );
$$;

-- Change le niveau d'un compte agent existant. Réservé à la direction (et à
-- Mégane), pour éviter qu'un compte agent restreint ne se donne les pleins
-- pouvoirs lui-même.
create or replace function public.set_agent_level(p_user_id uuid, p_level text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_direction() then
    raise exception 'Réservé aux comptes direction';
  end if;
  if p_level not in ('agent', 'direction') then
    raise exception 'Niveau invalide : %', p_level;
  end if;

  update public.profiles set agent_level = p_level where id = p_user_id and role = 'agent';
end;
$$;


-- ============================================================
-- 2. Catégorie tarifaire usager, sans date de naissance
-- ============================================================
-- Décision de Mégane (16/09/2026) : pas de date de naissance collectée à
-- l'inscription (RGPD, donnée sensible pas nécessaire). À la place, un agent
-- fixe la catégorie en personne à la validation de la préinscription, après
-- vérification d'un justificatif (pièce d'identité / justificatif de domicile,
-- déjà demandés à l'inscription physique). Corrigible ensuite si l'agent s'est
-- trompé de case, par n'importe quel agent (ce n'est pas une action sensible
-- comme le fichage ou les niveaux d'accès).
--
-- 'mineur'  : -16 ans, accès restreint (voir books.adult_only plus bas)
-- 'majeur'  : tarif plein
-- 'gratuit' : personnes sans emploi (chômeurs, RSA, retraités…), même accès
--             qu'un compte majeur, juste exempté du tarif

alter table public.profiles
  add column if not exists tariff_category text check (tariff_category in ('mineur', 'majeur', 'gratuit'));

comment on column public.profiles.tariff_category is 'Catégorie tarifaire fixée par un agent après vérification en personne (pas de date de naissance stockée). Corrigible si erreur de saisie.';

-- N'importe quel agent (pas seulement la direction) peut fixer ou corriger
-- cette catégorie : c'est une saisie de routine à la préinscription, pas une
-- action sensible comme le fichage ou les niveaux d'accès.
create or replace function public.set_tariff_category(p_user_id uuid, p_category text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  if p_category not in ('mineur', 'majeur', 'gratuit') then
    raise exception 'Catégorie invalide : %', p_category;
  end if;

  update public.profiles set tariff_category = p_category where id = p_user_id;
end;
$$;

-- ============================================================
-- 3. Livres réservés aux adultes
-- ============================================================
-- Plus flexible qu'une restriction par catégorie entière : certains livres
-- précis d'une catégorie donnée peuvent être réservés aux adultes, le reste de
-- la catégorie restant ouvert aux comptes mineurs.

alter table public.books
  add column if not exists adult_only boolean not null default false;

comment on column public.books.adult_only is 'Réservé aux comptes majeurs/gratuité. Un compte mineur ne peut ni le réserver ni l''emprunter au comptoir.';

-- Blocage dans enforce_reservation_limits() (Click & Collect + Bibliothèque Libre)
create or replace function public.enforce_reservation_limits()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_category text;
  v_is_new_release boolean := false;
  v_is_jeunesse boolean;
  v_adult_only boolean := false;
  v_active_count integer;
  v_new_release_count integer;
  v_user_commune bigint;
  v_flagged boolean;
  v_tariff_category text;
  v_max_general integer;
  v_max_jeunesse integer;
  v_max_new_release integer;
  v_restricted_categories text[];
  v_blocks_new_release boolean;
begin
  if tg_table_name = 'reservations' then
    select category, coalesce(is_new_release, false), coalesce(adult_only, false)
    into v_category, v_is_new_release, v_adult_only
    from public.books where id = new.book_id;
  else
    select category into v_category from public.free_books where id = new.free_book_id;
  end if;

  v_is_jeunesse := (v_category = 'Jeunesse');

  select commune_id, coalesce(flagged, false), tariff_category
  into v_user_commune, v_flagged, v_tariff_category
  from public.profiles where id = new.user_id;

  if v_tariff_category = 'mineur' and v_adult_only then
    raise exception 'Ce livre est réservé aux comptes majeurs.';
  end if;

  select
    coalesce(max_loans_general, 3), coalesce(max_loans_jeunesse, 3), coalesce(max_loans_new_releases, 1),
    coalesce(flagged_restricted_categories, '{}'), coalesce(flagged_blocks_new_releases, true)
  into v_max_general, v_max_jeunesse, v_max_new_release, v_restricted_categories, v_blocks_new_release
  from public.communes where id = v_user_commune;

  v_max_general := coalesce(v_max_general, 3);
  v_max_jeunesse := coalesce(v_max_jeunesse, 3);
  v_max_new_release := coalesce(v_max_new_release, 1);
  v_restricted_categories := coalesce(v_restricted_categories, '{}');
  v_blocks_new_release := coalesce(v_blocks_new_release, true);

  if v_flagged and v_category = any(v_restricted_categories) then
    raise exception 'Cet usager est actuellement restreint et ne peut pas emprunter dans la catégorie « % ».', v_category;
  end if;

  if v_flagged and v_blocks_new_release and v_is_new_release then
    raise exception 'Cet usager est actuellement restreint et ne peut pas emprunter les nouveautés.';
  end if;

  if tg_table_name = 'reservations' then
    select count(*) into v_active_count
    from public.reservations r
    join public.books b on b.id = r.book_id
    where r.user_id = new.user_id and r.status in ('preparation', 'pret')
      and coalesce(b.category = 'Jeunesse', false) = coalesce(v_is_jeunesse, false);
  else
    select count(*) into v_active_count
    from public.free_book_loans l
    join public.free_books fb on fb.id = l.free_book_id
    where l.user_id = new.user_id and l.status in ('preparation', 'pret')
      and coalesce(fb.category = 'Jeunesse', false) = coalesce(v_is_jeunesse, false);
  end if;

  if v_is_jeunesse then
    if v_active_count >= v_max_jeunesse then
      raise exception 'Limite atteinte : % livres jeunesse maximum en cours à la fois.', v_max_jeunesse;
    end if;
  elsif tg_table_name = 'reservations' then
    if v_active_count >= v_max_general then
      raise exception 'Limite atteinte : % livres maximum en cours à la fois (hors jeunesse). Rapportez-en un pour en réserver un nouveau, ou prenez un livre hors condition avec « Prendre ce livre ».', v_max_general;
    end if;
  else
    if v_active_count >= v_max_general then
      raise exception 'Limite atteinte : % livres hors condition maximum en cours à la fois (hors jeunesse). Rapportez-en un pour en prendre un nouveau.', v_max_general;
    end if;
  end if;

  if v_is_new_release and tg_table_name = 'reservations' then
    select count(*) into v_new_release_count
    from public.reservations r
    join public.books b on b.id = r.book_id
    where r.user_id = new.user_id and r.status in ('preparation', 'pret') and coalesce(b.is_new_release, false);

    if v_new_release_count >= v_max_new_release then
      raise exception 'Limite atteinte : % nouveauté(s) maximum en cours à la fois.', v_max_new_release;
    end if;
  end if;

  return new;
end;
$$;

-- Même blocage sur le prêt comptoir direct (scan_checkout)
create or replace function public.scan_checkout(p_barcode text, p_subscriber_number text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_book public.books;
  v_user_id uuid;
  v_user_commune bigint;
  v_user_flagged boolean;
  v_user_tariff_category text;
  v_reservation_id bigint;
  v_scope text;
  v_duration integer;
  v_due timestamptz;
  v_agent_commune bigint;
  v_restricted_categories text[];
  v_blocks_new_release boolean;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_copy from public.book_copies where barcode = trim(p_barcode);
  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Code-barres inconnu.');
  end if;

  select * into v_book from public.books where id = v_copy.book_id;

  select id, commune_id, coalesce(flagged, false), tariff_category
  into v_user_id, v_user_commune, v_user_flagged, v_user_tariff_category
  from public.profiles where subscriber_number = trim(p_subscriber_number);

  if v_user_id is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun usager ne porte ce numéro d''abonné.');
  end if;

  if v_user_tariff_category = 'mineur' and coalesce(v_book.adult_only, false) then
    return jsonb_build_object('ok', false, 'message', 'Ce livre est réservé aux comptes majeurs.');
  end if;

  if v_copy.status = 'borrowed' then
    return jsonb_build_object('ok', false, 'message', 'Cet exemplaire est déjà emprunté.');
  end if;

  if v_copy.status in ('in_transit', 'processing', 'lost', 'withdrawn') then
    return jsonb_build_object('ok', false,
      'message', 'Cet exemplaire n''est pas empruntable pour le moment (' || v_copy.status || ').');
  end if;

  select coalesce(flagged_restricted_categories, '{}'), coalesce(flagged_blocks_new_releases, true)
  into v_restricted_categories, v_blocks_new_release
  from public.communes where id = v_user_commune;

  if v_user_flagged and v_book.category = any(coalesce(v_restricted_categories, '{}')) then
    return jsonb_build_object('ok', false,
      'message', 'Cet usager est actuellement restreint et ne peut pas emprunter dans la catégorie « ' || v_book.category || ' ».');
  end if;

  if v_user_flagged and coalesce(v_blocks_new_release, true) and coalesce(v_book.is_new_release, false) then
    return jsonb_build_object('ok', false, 'message', 'Cet usager est actuellement restreint et ne peut pas emprunter les nouveautés.');
  end if;

  if v_copy.status = 'reserved' then
    select r.id into v_reservation_id
    from public.reservations r
    where r.book_id = v_copy.book_id
      and r.user_id = v_user_id
      and r.status in ('pret', 'preparation')
    order by r.created_at
    limit 1;

    if v_reservation_id is null then
      return jsonb_build_object('ok', false,
        'message', 'Cet exemplaire est mis de côté pour un autre usager.');
    end if;
  end if;

  v_agent_commune := coalesce(public.agent_commune_id(), v_copy.current_commune_id);

  select co.lending_scope into v_scope
  from public.communes cm
  join public.communities co on co.id = cm.community_id
  where cm.id = v_copy.current_commune_id;

  v_duration := public.effective_loan_duration_days(v_book.id, v_copy.current_commune_id);

  if v_scope = 'commune' and v_user_commune is distinct from v_copy.current_commune_id then
    return jsonb_build_object('ok', false,
      'message', 'Cet usager est inscrit dans une autre commune, et le contrat limite le prêt à la médiathèque de sa commune.');
  end if;

  v_due := now() + (v_duration || ' days')::interval;

  insert into public.loans (
    copy_id, user_id, reservation_id,
    borrowed_at_commune_id, due_at, borrowed_by_agent
  ) values (
    v_copy.id, v_user_id, v_reservation_id,
    v_copy.current_commune_id, v_due, auth.uid()
  );

  update public.book_copies set status = 'borrowed' where id = v_copy.id;

  if v_reservation_id is not null then
    update public.reservations
      set status = 'recupere', return_due_at = v_due
      where id = v_reservation_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'title', v_book.title,
    'author', v_book.author,
    'due_at', v_due,
    'from_reservation', v_reservation_id is not null,
    'message', 'Emprunt enregistré, à rendre avant le ' || to_char(v_due, 'DD/MM/YYYY') || '.'
  );
end;
$$;


-- ============================================================
-- 4. Tarifs par médiathèque, éditables uniquement par la direction
-- ============================================================
-- Pas de vrais montants pour l'instant (Mégane ne les a pas encore) : les
-- colonnes existent, à 0 par défaut. `tariff_updated_at/by` permettent de
-- retrouver qui a changé les tarifs et quand (utile d'une année sur l'autre).

alter table public.communes
  add column if not exists tariff_mineur_cents integer not null default 0,
  add column if not exists tariff_majeur_cents integer not null default 0,
  add column if not exists tariff_gratuit_cents integer not null default 0,
  add column if not exists tariff_updated_at timestamptz,
  add column if not exists tariff_updated_by uuid references auth.users(id);

comment on column public.communes.tariff_gratuit_cents is 'Presque toujours 0 : catégorie gratuité (chômeurs, RSA, retraités…). Existe quand même pour une médiathèque qui voudrait un tarif symbolique.';

-- ============================================================
-- 5. Restriction réelle d'un compte agent (pas seulement l'interface)
-- ============================================================
-- Catalogue et agenda culturel passent de is_agent() (tous les agents) à
-- is_direction() (direction + super_admin) : un compte agent restreint ne
-- peut plus ajouter/modifier/supprimer un livre ni un événement, même en
-- appelant directement l'API Supabase. Emprunt/retour et préinscriptions
-- restent ouverts à tous les agents (policies is_agent() déjà en place,
-- non touchées ici) : c'est bien ce que ce niveau doit encore pouvoir faire.

drop policy if exists "Un agent ajoute des livres" on public.books;
drop policy if exists "Un agent modifie les livres" on public.books;
drop policy if exists "Un agent supprime des livres" on public.books;

create policy "La direction ajoute des livres"
  on public.books for insert
  with check (public.is_direction());

create policy "La direction modifie les livres"
  on public.books for update
  using (public.is_direction());

create policy "La direction supprime des livres"
  on public.books for delete
  using (public.is_direction());

drop policy if exists "Un agent ou l'administratrice ajoute des événements" on public.events;
drop policy if exists "Un agent ou l'administratrice modifie les événements" on public.events;
drop policy if exists "Un agent ou l'administratrice supprime des événements" on public.events;

create policy "La direction ajoute des événements"
  on public.events for insert
  with check (public.is_direction());

create policy "La direction modifie les événements"
  on public.events for update
  using (public.is_direction());

create policy "La direction supprime des événements"
  on public.events for delete
  using (public.is_direction());


-- ============================================================
-- 6. Âge conseillé sur le catalogue principal (déjà présent sur Top
--    Jeunesse uniquement, voir sql/add_top_jeunesse.sql)
-- ============================================================

alter table public.books add column if not exists age_range text;
comment on column public.books.age_range is 'Âge conseillé en texte libre (ex. "À partir de 9 ans"), affiché dans le catalogue usager. Informatif, ne bloque rien (voir adult_only pour un vrai blocage).';


create or replace function public.update_commune_tariffs(
  p_commune_id bigint, p_mineur_cents integer, p_majeur_cents integer, p_gratuit_cents integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;

  update public.communes
    set tariff_mineur_cents = p_mineur_cents,
        tariff_majeur_cents = p_majeur_cents,
        tariff_gratuit_cents = p_gratuit_cents,
        tariff_updated_at = now(),
        tariff_updated_by = auth.uid()
    where id = p_commune_id;
end;
$$;
