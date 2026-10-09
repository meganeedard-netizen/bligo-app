-- Carte famille et ressources numériques (09/10/2026)
-- ============================================================
-- Carte famille, telle que précisée par Mégane le 09/10/2026 : UN SEUL
-- compte (une adresse e-mail, une carte, un numéro d'abonné) partagé par
-- toute la famille (parents, frères et sœurs se connectent avec le même
-- compte). C'est une catégorie tarifaire de plus (« famille »), avec un
-- tarif et un quota global de documents en cours fixés par la médiathèque.
-- Ressources numériques : liens vers les services de la médiathèque
-- (livres numériques, presse en ligne…), gérés par la direction, affichés
-- dans le profil usager.
-- À exécuter APRÈS add_renewal_holds_membership.sql.


-- ============================================================
-- 1. Catégorie tarifaire « famille »
-- ============================================================
alter table public.profiles drop constraint if exists profiles_tariff_category_check;
alter table public.profiles add constraint profiles_tariff_category_check
  check (tariff_category is null or tariff_category in ('mineur', 'majeur', 'gratuit', 'famille'));

alter table public.communes add column if not exists tariff_famille_cents integer not null default 0;
alter table public.communes add column if not exists family_max_loans integer not null default 15;

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
  if p_category not in ('mineur', 'majeur', 'gratuit', 'famille') then
    raise exception 'Catégorie invalide : %', p_category;
  end if;

  update public.profiles set tariff_category = p_category where id = p_user_id;
end;
$$;

-- Catégorie déclarée par l'usager en préinscription (non vérifiée : l'agent
-- confirme à la validation).
create or replace function public.declare_my_category(p_category text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_category not in ('majeur', 'mineur', 'famille') then
    raise exception 'Catégorie invalide';
  end if;
  update public.profiles set tariff_category = p_category
  where id = auth.uid() and coalesce(registration_status, 'pre_inscrit') <> 'valide';
end;
$$;

create or replace function public.update_commune_family_settings(p_commune_id bigint, p_tariff_cents integer, p_max_loans integer)
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
    set tariff_famille_cents = greatest(0, coalesce(p_tariff_cents, 0)),
        family_max_loans = greatest(1, coalesce(p_max_loans, 15))
    where id = p_commune_id;
end;
$$;

-- Documents en cours sur un compte famille (prêts non rendus + réservations
-- actives) et quota de sa médiathèque.
create or replace function public.family_usage(p_user_id uuid)
returns table (used bigint, max_loans integer)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*) from public.loans where user_id = p_user_id and returned_at is null)
    + (select count(*) from public.reservations where user_id = p_user_id and status in ('preparation', 'pret')),
    (select coalesce(c.family_max_loans, 15) from public.profiles p left join public.communes c on c.id = p.commune_id where p.id = p_user_id);
$$;

create or replace function public.family_quota_reached(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select u.used >= u.max_loans from public.family_usage(p_user_id) u), false);
$$;


-- ============================================================
-- 2. Quotas : la carte famille remplace les quotas individuels
--    (reprend enforce_reservation_limits et scan_checkout à l'identique,
--    avec la seule règle famille en plus)
-- ============================================================
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

  -- Carte famille (09/10/2026) : un seul compte partagé par toute la
  -- famille, avec un quota global (prêts + réservations) à la place des
  -- quotas individuels.
  if v_tariff_category = 'famille' and tg_table_name = 'reservations' then
    if public.family_quota_reached(new.user_id) then
      raise exception 'Le quota de la carte famille est atteint : un document doit être rendu avant une nouvelle réservation.';
    end if;
    return new;
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
  v_membership text;
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

  v_membership := public.membership_status(v_user_id, v_copy.current_commune_id);
  if v_membership <> 'ok' then
    return jsonb_build_object('ok', false, 'message', public.membership_error_message(v_membership));
  end if;

  if v_user_tariff_category = 'famille' and public.family_quota_reached(v_user_id) then
    return jsonb_build_object('ok', false, 'message', 'Le quota de la carte famille est atteint : un document doit être rendu avant un nouvel emprunt.');
  end if;

  v_duration := public.effective_loan_duration_days(v_book.id, v_copy.current_commune_id);
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
-- 3. Ressources numériques
-- ============================================================
create table if not exists public.digital_resources (
  id bigint generated always as identity primary key,
  commune_id bigint not null references public.communes(id) on delete cascade,
  name text not null,
  kind text not null default 'autre' check (kind in ('livres', 'presse', 'autoformation', 'musique', 'cinema', 'jeunesse', 'autre')),
  url text not null,
  description text,
  sort_order integer not null default 100,
  created_at timestamptz not null default now()
);

alter table public.digital_resources enable row level security;
drop policy if exists "Tout le monde voit les ressources numériques" on public.digital_resources;
create policy "Tout le monde voit les ressources numériques"
  on public.digital_resources for select using (true);
drop policy if exists "La direction gère ses ressources numériques" on public.digital_resources;
create policy "La direction gère ses ressources numériques"
  on public.digital_resources for all
  using (public.is_super_admin() or (public.is_direction() and commune_id = public.agent_commune_id()))
  with check (public.is_super_admin() or (public.is_direction() and commune_id = public.agent_commune_id()));

grant execute on function public.update_commune_family_settings(bigint, integer, integer) to authenticated;
grant execute on function public.family_usage(uuid) to authenticated;
grant execute on function public.declare_my_category(text) to authenticated;
grant execute on function public.set_tariff_category(uuid, text) to authenticated;
