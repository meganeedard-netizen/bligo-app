-- BliGO — Panier et commande (16/10/2026, retours de test de Mégane)
--
-- 1. Nouveau statut « panier » : « Ajouter au panier » ne réserve plus le
--    livre directement. Le panier est validé par « Valider ma commande »
--    (validate_cart), la commande passe alors « en préparation ».
-- 2. Les 30 minutes pour modifier sa commande partent de la validation
--    (ordered_at) : l'usager peut retirer un livre pendant ce délai, ensuite
--    c'est bloqué. Le back-office masque la commande pendant ces 30 minutes.
-- 3. Limite de documents corrigée : elle compte le panier, les commandes en
--    cours ET les livres déjà empruntés (prêts non rendus). Avant, seuls les
--    livres « en préparation » ou « prêts » étaient comptés.
-- 4. File d'attente optionnelle par médiathèque (communes.holds_enabled).
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > Run.

-- ============================================================
-- 1. Statut « panier » + date de validation de la commande
-- ============================================================
alter table public.reservations drop constraint if exists reservations_status_check;
alter table public.reservations add constraint reservations_status_check
  check (status in ('panier', 'preparation', 'pret', 'recupere', 'expiree'));

alter table public.reservations add column if not exists ordered_at timestamptz;
update public.reservations set ordered_at = created_at where ordered_at is null and status <> 'panier';

-- ============================================================
-- 2. Retirer un livre : toujours possible dans le panier, et pendant
--    30 minutes après la validation de la commande
-- ============================================================
drop policy if exists "Un usager annule sa réservation tant qu'elle est en préparation" on public.reservations;
drop policy if exists "Un usager retire un livre de son panier ou de sa commande" on public.reservations;
create policy "Un usager retire un livre de son panier ou de sa commande"
  on public.reservations for delete
  using (
    auth.uid() = user_id
    and (
      status = 'panier'
      or (status = 'preparation' and coalesce(ordered_at, created_at) > now() - interval '30 minutes')
    )
  );

-- ============================================================
-- 3. Valider ma commande
-- ============================================================
create or replace function public.validate_cart()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_unavailable text[];
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;

  -- Un livre du panier emprunté entre-temps par quelqu'un d'autre reste dans
  -- le panier : on le signale au lieu de l'envoyer à la médiathèque.
  select array_agg(b.title order by b.title) into v_unavailable
  from public.reservations r
  join public.books b on b.id = r.book_id
  where r.user_id = auth.uid() and r.status = 'panier' and not coalesce(b.available, false);

  update public.reservations r
    set status = 'preparation', ordered_at = now()
  from public.books b
  where b.id = r.book_id
    and r.user_id = auth.uid() and r.status = 'panier' and coalesce(b.available, false);
  get diagnostics v_count = row_count;

  return jsonb_build_object('ok', v_count > 0, 'count', v_count, 'unavailable', coalesce(to_jsonb(v_unavailable), '[]'::jsonb));
end;
$$;

grant execute on function public.validate_cart() to authenticated;

-- ============================================================
-- 4. Limite de documents : panier + commandes en cours + prêts non rendus
--    (reprend la version de add_family_and_digital.sql, en ajoutant le
--    panier, les prêts en cours et le contrôle de doublon)
-- ============================================================
create or replace function public.family_usage(p_user_id uuid)
returns table (used bigint, max_loans integer)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*) from public.loans where user_id = p_user_id and returned_at is null)
    + (select count(*) from public.reservations where user_id = p_user_id and status in ('panier', 'preparation', 'pret')),
    (select coalesce(c.family_max_loans, 15) from public.profiles p left join public.communes c on c.id = p.commune_id where p.id = p_user_id);
$$;

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

    -- Même livre déjà dans le panier, en commande ou chez l'usager.
    if exists (
      select 1 from public.reservations r
      where r.user_id = new.user_id and r.book_id = new.book_id
        and r.status in ('panier', 'preparation', 'pret')
    ) or exists (
      select 1 from public.loans l join public.book_copies c on c.id = l.copy_id
      where l.user_id = new.user_id and c.book_id = new.book_id and l.returned_at is null
    ) then
      raise exception 'Tu as déjà ce livre dans ton panier, ta commande ou chez toi.';
    end if;
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

  if v_tariff_category = 'famille' and tg_table_name = 'reservations' then
    if public.family_quota_reached(new.user_id) then
      raise exception 'Limite atteinte : le nombre maximum de documents de la carte famille est atteint.';
    end if;
    return new;
  end if;

  if tg_table_name = 'reservations' then
    select
      (select count(*)
         from public.reservations r
         join public.books b on b.id = r.book_id
        where r.user_id = new.user_id and r.status in ('panier', 'preparation', 'pret')
          and coalesce(b.category = 'Jeunesse', false) = coalesce(v_is_jeunesse, false))
      + (select count(*)
           from public.loans l
           join public.book_copies c on c.id = l.copy_id
           join public.books b on b.id = c.book_id
          where l.user_id = new.user_id and l.returned_at is null
            and coalesce(b.category = 'Jeunesse', false) = coalesce(v_is_jeunesse, false))
    into v_active_count;
  else
    select count(*) into v_active_count
    from public.free_book_loans l
    join public.free_books fb on fb.id = l.free_book_id
    where l.user_id = new.user_id and l.status in ('preparation', 'pret')
      and coalesce(fb.category = 'Jeunesse', false) = coalesce(v_is_jeunesse, false);
  end if;

  if v_is_jeunesse then
    if v_active_count >= v_max_jeunesse then
      raise exception 'Limite atteinte : % documents jeunesse maximum à la fois (panier, commande et emprunts compris).', v_max_jeunesse;
    end if;
  elsif tg_table_name = 'reservations' then
    if v_active_count >= v_max_general then
      raise exception 'Limite atteinte : % documents maximum à la fois (panier, commande et emprunts compris).', v_max_general;
    end if;
  else
    if v_active_count >= v_max_general then
      raise exception 'Limite atteinte : % livres hors condition maximum en cours à la fois (hors jeunesse). Rapporte-en un pour en prendre un nouveau.', v_max_general;
    end if;
  end if;

  if v_is_new_release and tg_table_name = 'reservations' then
    select
      (select count(*)
         from public.reservations r
         join public.books b on b.id = r.book_id
        where r.user_id = new.user_id and r.status in ('panier', 'preparation', 'pret') and coalesce(b.is_new_release, false))
      + (select count(*)
           from public.loans l
           join public.book_copies c on c.id = l.copy_id
           join public.books b on b.id = c.book_id
          where l.user_id = new.user_id and l.returned_at is null and coalesce(b.is_new_release, false))
    into v_new_release_count;

    if v_new_release_count >= v_max_new_release then
      raise exception 'Limite atteinte : % nouveauté(s) maximum à la fois.', v_max_new_release;
    end if;
  end if;

  return new;
end;
$$;

-- ============================================================
-- 5. Journal d'activité : un livre ajouté au panier n'est pas encore une
--    réservation ; elle est comptée à la validation de la commande
-- ============================================================
create or replace function public.trg_log_reservations()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commune bigint;
begin
  select commune_id into v_commune from public.profiles where id = new.user_id;

  if tg_op = 'INSERT' then
    if new.status <> 'panier' then
      perform public.log_activity('reservation_created', v_commune, 'reservation', new.id::text,
        jsonb_build_object('book_id', new.book_id));
    end if;
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    if old.status = 'panier' then
      perform public.log_activity('reservation_created', v_commune, 'reservation', new.id::text,
        jsonb_build_object('book_id', new.book_id));
    else
      perform public.log_activity('reservation_status_changed', v_commune, 'reservation', new.id::text,
        jsonb_build_object('from', old.status, 'to', new.status));
    end if;
  end if;
  return new;
end;
$$;

-- ============================================================
-- 6. File d'attente activable par médiathèque
-- ============================================================
alter table public.communes add column if not exists holds_enabled boolean not null default true;

create or replace function public.check_holds_enabled()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.books b join public.communes c on c.id = b.commune_id
    where b.id = new.book_id and not c.holds_enabled
  ) then
    raise exception 'Cette médiathèque ne propose pas de file d''attente. Ajoute le livre à ta liste d''envies pour le retrouver plus tard.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_check_holds_enabled on public.holds;
create trigger trg_check_holds_enabled
  before insert on public.holds
  for each row execute function public.check_holds_enabled();

create or replace function public.update_commune_holds_setting(p_commune_id bigint, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;
  update public.communes set holds_enabled = coalesce(p_enabled, true) where id = p_commune_id;
end;
$$;

grant execute on function public.update_commune_holds_setting(bigint, boolean) to authenticated;

-- ============================================================
-- 7. Statistiques SIGB : les livres restés dans un panier ne comptent pas
--    (reprend sql/add_sigb_annual_stats.sql, une seule ligne ajoutée)
-- ============================================================
create or replace function public.sigb_annual_stats(p_commune_id bigint, p_year integer)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_year_start timestamptz := make_timestamptz(p_year, 1, 1, 0, 0, 0, 'UTC');
  v_year_end timestamptz := make_timestamptz(p_year + 1, 1, 1, 0, 0, 0, 'UTC');
  v_result jsonb;
begin
  if not (public.is_direction() or public.is_super_admin()) then
    raise exception 'Réservé à la direction';
  end if;

  select jsonb_build_object(
    'c2_notices_total', (
      select count(*) from public.books where commune_id = p_commune_id and equipped = true
    ),
    'c2_notices_added_year', (
      select count(*) from public.books
      where commune_id = p_commune_id and created_at >= v_year_start and created_at < v_year_end
    ),
    'd1_fonds_adultes', (
      select count(*) from public.books
      where commune_id = p_commune_id and equipped = true and coalesce(category, '') <> 'Jeunesse'
    ),
    'd1_fonds_jeunesse', (
      select count(*) from public.books
      where commune_id = p_commune_id and equipped = true and category = 'Jeunesse'
    ),
    'd1_acquisitions_year', (
      select count(*) from public.books
      where commune_id = p_commune_id and created_at >= v_year_start and created_at < v_year_end
    ),
    'd1_eliminations_year', (
      select count(*) from public.activity_events
      where commune_id = p_commune_id and event_type = 'copy_status_changed'
        and metadata->>'to' = 'withdrawn'
        and occurred_at >= v_year_start and occurred_at < v_year_end
    ),
    'e1_inscrits_actifs', (
      select count(*) from public.profiles
      where commune_id = p_commune_id and commune_confirmed = true
    ),
    'e1_nouveaux_inscrits_year', (
      select count(*) from public.profiles
      where commune_id = p_commune_id and created_at >= v_year_start and created_at < v_year_end
    ),
    'e1_emprunteurs_actifs_year', (
      select count(distinct l.user_id) from public.loans l
      where l.borrowed_at_commune_id = p_commune_id
        and l.borrowed_at >= v_year_start and l.borrowed_at < v_year_end
    ),
    'e2_prets_total_year', (
      select count(*) from public.loans l
      where l.borrowed_at_commune_id = p_commune_id
        and l.borrowed_at >= v_year_start and l.borrowed_at < v_year_end
    ),
    'e2_prets_jeunesse_year', (
      select count(*) from public.loans l
      join public.book_copies c on c.id = l.copy_id
      join public.books b on b.id = c.book_id
      where l.borrowed_at_commune_id = p_commune_id and b.category = 'Jeunesse'
        and l.borrowed_at >= v_year_start and l.borrowed_at < v_year_end
    ),
    'e2_prets_adultes_year', (
      select count(*) from public.loans l
      join public.book_copies c on c.id = l.copy_id
      join public.books b on b.id = c.book_id
      where l.borrowed_at_commune_id = p_commune_id and coalesce(b.category, '') <> 'Jeunesse'
        and l.borrowed_at >= v_year_start and l.borrowed_at < v_year_end
    ),
    'e3_reservations_year', (
      select count(*) from public.reservations r
      join public.profiles p on p.id = r.user_id
      where p.commune_id = p_commune_id
        and r.status <> 'panier'
        and r.created_at >= v_year_start and r.created_at < v_year_end
    ),
    'frequentation_year', (
      select coalesce(sum(count), 0) from public.visitor_entries
      where commune_id = p_commune_id
        and occurred_at >= v_year_start and occurred_at < v_year_end
    )
  ) into v_result;

  return v_result;
end;
$$;

-- ============================================================
-- 8. Vérification : compte de test de Nicolas (plus de 3 livres réservés)
--    Le résultat s'affiche sous l'éditeur après « Run ».
-- ============================================================
select
  p.full_name,
  p.tariff_category as categorie_tarifaire,
  c.name as mediatheque,
  coalesce(c.max_loans_general, 3) as max_adulte,
  coalesce(c.max_loans_jeunesse, 3) as max_jeunesse,
  (select count(*) from public.reservations r where r.user_id = p.id and r.status in ('panier', 'preparation', 'pret')) as panier_et_commandes,
  (select count(*) from public.loans l where l.user_id = p.id and l.returned_at is null) as prets_non_rendus
from auth.users u
join public.profiles p on p.id = u.id
left join public.communes c on c.id = p.commune_id
where u.email = 'nicop421@gmail.com';
