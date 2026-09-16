-- BliGO — Retour de terrain du 14/09/2026, points 4, 5, 6 et 8 (16/09/2026)
-- Quotas et durée de prêt paramétrables par commune, délai par livre avec édition
-- en masse, pénalités de retard, usager « fiché ».
--
-- Migration ADDITIVE, à exécuter après add_copies_communities_loans.sql et
-- add_scan_operations.sql (redéfinit scan_checkout et scan_return en entier,
-- inutile de revenir modifier ces anciens fichiers).
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run


-- ============================================================
-- 1. Réglages par commune (médiathèque), en plus des réglages de
--    communauté déjà existants sur `communities`
-- ============================================================
-- Une valeur ici, quand elle est renseignée, l'emporte sur le réglage de la
-- communauté de communes. `loan_duration_days` reste nullable : null = on
-- garde le réglage de la communauté (comportement actuel inchangé tant que
-- Mégane ne configure rien de nouveau).

alter table public.communes
  add column if not exists max_loans_general integer not null default 3,
  add column if not exists max_loans_jeunesse integer not null default 3,
  add column if not exists max_loans_new_releases integer not null default 1,
  add column if not exists loan_duration_days integer,
  add column if not exists new_release_loan_duration_days integer not null default 7,
  add column if not exists late_fee_per_day_cents integer not null default 100,
  add column if not exists late_fee_grace_days integer not null default 7,
  add column if not exists flagged_restricted_categories text[] not null default '{}',
  add column if not exists flagged_blocks_new_releases boolean not null default true;

comment on column public.communes.max_loans_general is 'Nombre de livres empruntables en même temps, hors jeunesse. Ex. 5.';
comment on column public.communes.max_loans_new_releases is 'Parmi le quota général, combien peuvent être des nouveautés (délai raccourci).';
comment on column public.communes.loan_duration_days is 'Durée de prêt par défaut de cette médiathèque, en jours. Null = hérite de la communauté de communes.';
comment on column public.communes.late_fee_per_day_cents is 'Pénalité de retard, en centimes par jour, appliquée après la franchise.';
comment on column public.communes.late_fee_grace_days is 'Nombre de jours de retard tolérés avant que la pénalité ne commence à courir.';
comment on column public.communes.flagged_restricted_categories is 'Catégories interdites à un usager « fiché » dans cette médiathèque (vide = aucune restriction de catégorie).';


-- ============================================================
-- 2. Délai de prêt réglable par livre, éditable en masse
-- ============================================================

alter table public.books
  add column if not exists loan_duration_days_override integer,
  add column if not exists is_new_release boolean not null default false;

comment on column public.books.loan_duration_days_override is 'Délai de prêt propre à ce livre, en jours. Prioritaire sur tous les autres réglages. Null = pas de réglage particulier.';
comment on column public.books.is_new_release is 'Nouveauté : soumis au sous-quota et au délai raccourci de la médiathèque.';


-- ============================================================
-- 3. Usager « fiché »
-- ============================================================
-- Restriction de comportement, distincte du blocage de compte. Un usager fiché
-- garde son compte actif mais perd l'accès à certaines catégories et aux
-- nouveautés, selon ce que la médiathèque a configuré ci-dessus.

alter table public.profiles
  add column if not exists flagged boolean not null default false,
  add column if not exists flagged_at timestamptz,
  add column if not exists flagged_reason text;

create or replace function public.set_user_flagged(p_user_id uuid, p_flagged boolean, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  update public.profiles
    set flagged = p_flagged,
        flagged_at = case when p_flagged then now() else null end,
        flagged_reason = case when p_flagged then p_reason else null end
    where id = p_user_id;
end;
$$;


-- ============================================================
-- 4. Délai de prêt effectif d'un livre dans une médiathèque
-- ============================================================
-- Ordre de priorité : réglage du livre > nouveauté de la médiathèque >
-- réglage de la médiathèque > réglage de la communauté de communes > 21 jours.

create or replace function public.effective_loan_duration_days(p_book_id bigint, p_commune_id bigint)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select loan_duration_days_override from public.books where id = p_book_id),
    case when (select is_new_release from public.books where id = p_book_id)
      then (select new_release_loan_duration_days from public.communes where id = p_commune_id)
    end,
    (select loan_duration_days from public.communes where id = p_commune_id),
    (select co.loan_duration_days
       from public.communes cm join public.communities co on co.id = cm.community_id
       where cm.id = p_commune_id),
    21
  );
$$;


-- ============================================================
-- 5. Pénalité de retard, calculée à la demande (pas stockée)
-- ============================================================

create or replace function public.calculate_late_fee_cents(p_due_at timestamptz, p_returned_at timestamptz, p_commune_id bigint)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_due_at is null or p_returned_at is null or p_returned_at <= p_due_at then 0
    else greatest(0,
      extract(day from (p_returned_at - p_due_at))::int
      - coalesce((select late_fee_grace_days from public.communes where id = p_commune_id), 7)
    ) * coalesce((select late_fee_per_day_cents from public.communes where id = p_commune_id), 100)
  end;
$$;


-- ============================================================
-- 6. Limites d'emprunt : reprend enforce_reservation_limits() en
--    remplaçant le quota fixe (3+3) par les réglages de la commune de
--    l'usager, ajoute le sous-quota nouveautés et le blocage usager fiché.
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
  v_active_count integer;
  v_new_release_count integer;
  v_user_commune bigint;
  v_flagged boolean;
  v_max_general integer;
  v_max_jeunesse integer;
  v_max_new_release integer;
  v_restricted_categories text[];
  v_blocks_new_release boolean;
begin
  if tg_table_name = 'reservations' then
    select category, coalesce(is_new_release, false) into v_category, v_is_new_release
    from public.books where id = new.book_id;
  else
    select category into v_category from public.free_books where id = new.free_book_id;
  end if;

  v_is_jeunesse := (v_category = 'Jeunesse');

  select commune_id, coalesce(flagged, false) into v_user_commune, v_flagged
  from public.profiles where id = new.user_id;

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


-- ============================================================
-- 7. scan_checkout : délai effectif (livre > nouveauté > commune >
--    communauté) + blocage usager fiché sur les prêts comptoir
-- ============================================================

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

  select id, commune_id, coalesce(flagged, false) into v_user_id, v_user_commune, v_user_flagged
  from public.profiles where subscriber_number = trim(p_subscriber_number);

  if v_user_id is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun usager ne porte ce numéro d''abonné.');
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

  -- Réservation mise de côté : elle doit appartenir à l'usager qui se présente
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

  -- Règle de prêt de la communauté de communes
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
-- 8. scan_return : état du livre au retour, pénalité de retard
--    informative, fichage automatique
-- ============================================================
-- `p_condition` : 'bon', 'mauvais', ou null si l'agent ne renseigne rien
-- (aucun changement de comportement dans ce cas, comme avant).
--
-- Fichage automatique si l'état est mauvais, ou si le retard dépasse la
-- franchise configurée sur la commune de l'usager (par défaut 7 jours).
-- Un agent peut toujours retirer le fichage manuellement via set_user_flagged().

create or replace function public.scan_return(p_barcode text, p_condition text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_book public.books;
  v_loan public.loans;
  v_here bigint;
  v_returns_anywhere boolean;
  v_late boolean := false;
  v_transfer_created boolean := false;
  v_late_fee_cents integer := 0;
  v_user_commune bigint;
  v_grace_days integer;
  v_days_late integer;
  v_should_flag boolean := false;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  if p_condition is not null and p_condition not in ('bon', 'mauvais') then
    raise exception 'État de retour invalide : % (attendu bon ou mauvais)', p_condition;
  end if;

  select * into v_copy from public.book_copies where barcode = trim(p_barcode);
  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Code-barres inconnu.');
  end if;

  select * into v_book from public.books where id = v_copy.book_id;

  v_here := coalesce(public.agent_commune_id(), v_copy.current_commune_id);

  select co.returns_anywhere into v_returns_anywhere
  from public.communes cm
  join public.communities co on co.id = cm.community_id
  where cm.id = v_here;

  v_returns_anywhere := coalesce(v_returns_anywhere, true);

  if not v_returns_anywhere and v_here is distinct from v_copy.owner_commune_id then
    return jsonb_build_object('ok', false,
      'message', 'Ce livre appartient à une autre médiathèque, et le contrat impose de le rendre sur place.');
  end if;

  select * into v_loan from public.loans where copy_id = v_copy.id and returned_at is null;

  if v_loan.id is not null then
    v_late := now() > v_loan.due_at;

    select commune_id into v_user_commune from public.profiles where id = v_loan.user_id;
    select coalesce(late_fee_grace_days, 7) into v_grace_days from public.communes where id = v_user_commune;
    v_grace_days := coalesce(v_grace_days, 7);
    v_days_late := greatest(0, extract(day from (now() - v_loan.due_at))::int);
    v_late_fee_cents := public.calculate_late_fee_cents(v_loan.due_at, now(), v_user_commune);

    v_should_flag := (p_condition = 'mauvais') or (v_days_late > v_grace_days);

    update public.loans
      set returned_at = now(),
          returned_at_commune_id = v_here,
          returned_by_agent = auth.uid()
      where id = v_loan.id;

    if v_should_flag then
      perform public.set_user_flagged(
        v_loan.user_id, true,
        case
          when p_condition = 'mauvais' and v_days_late > v_grace_days then 'Livre rendu abîmé et en retard'
          when p_condition = 'mauvais' then 'Livre rendu abîmé'
          else 'Retard de plus de ' || v_grace_days || ' jours'
        end
      );
    end if;

    if v_loan.reservation_id is not null then
      update public.reservations set status = 'expiree' where id = v_loan.reservation_id;
    end if;
  end if;

  update public.book_copies
    set status = 'available',
        current_commune_id = v_here,
        condition = coalesce(p_condition, condition)
    where id = v_copy.id;

  if v_here is distinct from v_copy.owner_commune_id then
    insert into public.transfers (
      copy_id, from_commune_id, to_commune_id, status, requested_by, notes
    ) values (
      v_copy.id, v_here, v_copy.owner_commune_id, 'requested', auth.uid(),
      'Retour rendu dans une autre médiathèque'
    );
    v_transfer_created := true;
  end if;

  return jsonb_build_object(
    'ok', true,
    'title', v_book.title,
    'author', v_book.author,
    'had_loan', v_loan.id is not null,
    'was_late', v_late,
    'late_fee_cents', v_late_fee_cents,
    'user_flagged', v_should_flag,
    'needs_transfer', v_transfer_created,
    'shelf_location', v_copy.shelf_location,
    'message', case
      when v_transfer_created then 'Retour enregistré. Ce livre appartient à une autre médiathèque, il est à renvoyer.'
      when v_loan.id is null then 'Aucun prêt en cours pour cet exemplaire, il est remis en rayon.'
      when v_late_fee_cents > 0 then 'Retour enregistré, avec retard : ' || to_char(v_late_fee_cents / 100.0, 'FM999990.00') || ' € de pénalité.'
      when v_late then 'Retour enregistré, avec du retard (dans la franchise, aucune pénalité).'
      else 'Retour enregistré.'
    end
  );
end;
$$;
