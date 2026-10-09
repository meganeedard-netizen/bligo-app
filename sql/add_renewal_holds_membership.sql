-- Prolongation, file d'attente, validité d'adhésion et non-résidents (09/10/2026)
-- ============================================================
-- Règles validées par Mégane le 09/10/2026 :
--   1. Prolongation : +7 jours, une seule fois par prêt, impossible si le prêt
--      est déjà en retard ou si quelqu'un attend le livre. Usager ou agent.
--   2. File d'attente sur un livre emprunté : au retour, le premier de la file
--      reçoit une réservation mise de côté (48 h pour venir, comme le Click &
--      Collect), sinon on passe au suivant.
--   3. Validité de l'adhésion réglable par médiathèque : 12 mois glissants,
--      année civile, ou pas d'expiration (défaut, pour ne bloquer personne).
--   4. Non-résidents (cas de la Guadeloupe : emprunter dans la bibliothèque
--      d'une autre commune, hors de son intercommunalité) : l'usager demande
--      son inscription depuis l'appli ; chaque médiathèque refuse, accepte
--      gratuitement ou avec un supplément ; l'agent valide et encaisse.
-- À exécuter dans Supabase : SQL Editor > coller > Run.


-- ============================================================
-- 1. Réglages par médiathèque
-- ============================================================
alter table public.communes add column if not exists membership_validity text not null default 'none'
  check (membership_validity in ('rolling_12m', 'calendar_year', 'none'));
alter table public.communes add column if not exists non_resident_policy text not null default 'free'
  check (non_resident_policy in ('refuse', 'free', 'paid'));
alter table public.communes add column if not exists non_resident_fee_cents integer not null default 0;

alter table public.profiles add column if not exists membership_expires_at timestamptz;
alter table public.profiles add column if not exists membership_reminded_at timestamptz;

alter table public.loans add column if not exists renewal_count integer not null default 0;
-- Rappels de retour (créés par add_return_reminders_email.sql, pas forcément
-- encore exécutée) : remis à zéro par une prolongation.
alter table public.loans add column if not exists return_reminded boolean not null default false;
alter table public.loans add column if not exists overdue_reminded boolean not null default false;
alter table public.reservations add column if not exists return_reminded boolean not null default false;
alter table public.reservations add column if not exists overdue_reminded boolean not null default false;

-- Médiathèque où l'usager vient chercher sa réservation : null = sa commune
-- (comportement historique). Renseignée pour un non-résident qui réserve
-- dans le catalogue d'une autre médiathèque, et pour la file d'attente.
alter table public.reservations add column if not exists pickup_commune_id bigint references public.communes(id);


-- ============================================================
-- 2. Adhésion : date d'expiration et validité
-- ============================================================
create or replace function public.membership_expiry(p_commune_id bigint, p_from timestamptz)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select case coalesce((select membership_validity from public.communes where id = p_commune_id), 'none')
    when 'rolling_12m' then p_from + interval '12 months'
    when 'calendar_year' then (date_trunc('year', p_from) + interval '1 year' - interval '1 second')
    else null
  end;
$$;

-- Inscriptions dans une médiathèque autre que celle de sa commune.
create table if not exists public.memberships (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  commune_id bigint not null references public.communes(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'active', 'refused')),
  fee_cents integer not null default 0,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  validated_at timestamptz,
  validated_by uuid references auth.users(id),
  unique (user_id, commune_id)
);

alter table public.memberships enable row level security;

drop policy if exists "Un usager voit ses inscriptions" on public.memberships;
create policy "Un usager voit ses inscriptions"
  on public.memberships for select
  using (auth.uid() = user_id or public.is_super_admin()
    or (public.is_agent() and commune_id = public.agent_commune_id()));

-- L'usager peut-il emprunter / réserver dans cette médiathèque ?
-- Sa commune (ou une commune de son intercommunalité si le contrat ouvre le
-- prêt à tout le territoire) : selon la validité de son adhésion principale.
-- Ailleurs : seulement avec une inscription non-résident active et valide.
create or replace function public.membership_status(p_user_id uuid, p_commune_id bigint)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_home bigint;
  v_expires timestamptz;
  v_same_territory boolean := false;
  v_member public.memberships;
begin
  select commune_id, membership_expires_at into v_home, v_expires from public.profiles where id = p_user_id;

  if v_home is not null and p_commune_id is not null and v_home <> p_commune_id then
    select (h.community_id is not null and h.community_id = c.community_id and co.lending_scope = 'community')
    into v_same_territory
    from public.communes h
    join public.communes c on c.id = p_commune_id
    left join public.communities co on co.id = c.community_id
    where h.id = v_home;
  end if;

  if v_home is not null and (p_commune_id is null or v_home = p_commune_id or coalesce(v_same_territory, false)) then
    return case when v_expires is null or v_expires > now() then 'ok' else 'expired' end;
  end if;

  select * into v_member from public.memberships where user_id = p_user_id and commune_id = p_commune_id;
  if v_member.id is null or v_member.status <> 'active' then
    return 'not_member';
  end if;
  return case when v_member.expires_at is null or v_member.expires_at > now() then 'ok' else 'expired' end;
end;
$$;

create or replace function public.membership_error_message(p_status text)
returns text
language sql
immutable
as $$
  select case p_status
    when 'expired' then 'L''adhésion de cet usager a expiré : elle doit être renouvelée à l''accueil avant tout nouvel emprunt ou réservation.'
    when 'not_member' then 'Cet usager n''est pas inscrit dans cette médiathèque (non-résident) : il doit d''abord demander son inscription depuis l''appli BliGO.'
    else null
  end;
$$;

-- Validation d'une inscription : la date d'expiration est posée selon le
-- réglage de la médiathèque (reprend validate_registration à l'identique).
create or replace function public.validate_registration(p_user_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  if not public.is_agent() then
    raise exception 'Seul un agent peut valider une inscription.';
  end if;

  update public.profiles
  set registration_status = 'valide',
      validated_at = now(),
      validated_by = auth.uid(),
      membership_expires_at = public.membership_expiry(commune_id, now()),
      membership_reminded_at = null
  where id = p_user_id;

  insert into public.notifications (user_id, message)
  values (p_user_id, 'Votre inscription a été validée par la médiathèque ! Votre carte et votre QR code sont maintenant actifs dans votre profil.');
end;
$$;

-- Renouvellement par un agent (après paiement éventuel au comptoir) :
-- adhésion principale si p_commune_id est la commune de l'usager (ou null),
-- sinon son inscription non-résident dans cette médiathèque.
create or replace function public.renew_membership(p_user_id uuid, p_commune_id bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_home bigint;
  v_current timestamptz;
  v_new timestamptz;
  v_member public.memberships;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select commune_id, membership_expires_at into v_home, v_current from public.profiles where id = p_user_id;

  if p_commune_id is null or p_commune_id = v_home then
    v_new := public.membership_expiry(v_home, greatest(now(), coalesce(v_current, now())));
    update public.profiles set membership_expires_at = v_new, membership_reminded_at = null where id = p_user_id;
  else
    select * into v_member from public.memberships where user_id = p_user_id and commune_id = p_commune_id;
    if v_member.id is null then
      return jsonb_build_object('ok', false, 'message', 'Cet usager n''est pas inscrit dans cette médiathèque.');
    end if;
    v_new := public.membership_expiry(p_commune_id, greatest(now(), coalesce(v_member.expires_at, now())));
    update public.memberships set status = 'active', expires_at = v_new, validated_at = now(), validated_by = auth.uid()
      where id = v_member.id;
  end if;

  insert into public.notifications (user_id, message)
  values (p_user_id, case when v_new is null then 'Votre adhésion a été renouvelée.'
    else 'Votre adhésion a été renouvelée jusqu''au ' || to_char(v_new, 'DD/MM/YYYY') || '.' end);

  return jsonb_build_object('ok', true, 'expires_at', v_new,
    'message', case when v_new is null then 'Adhésion renouvelée (sans date d''expiration dans cette médiathèque).'
      else 'Adhésion renouvelée jusqu''au ' || to_char(v_new, 'DD/MM/YYYY') || '.' end);
end;
$$;

-- Réglages d'adhésion de la médiathèque (direction), comme update_commune_tariffs.
create or replace function public.update_commune_membership_settings(
  p_commune_id bigint, p_validity text, p_non_resident_policy text, p_non_resident_fee_cents integer
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
    set membership_validity = p_validity,
        non_resident_policy = p_non_resident_policy,
        non_resident_fee_cents = greatest(0, coalesce(p_non_resident_fee_cents, 0))
    where id = p_commune_id;
end;
$$;

-- Demande d'inscription non-résident depuis l'appli.
create or replace function public.request_membership(p_commune_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_home bigint;
  v_policy text;
  v_fee integer;
  v_name text;
  v_existing public.memberships;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;

  select commune_id into v_home from public.profiles where id = auth.uid();
  if v_home = p_commune_id then
    return jsonb_build_object('ok', false, 'message', 'C''est déjà la médiathèque de ta commune.');
  end if;

  select non_resident_policy, non_resident_fee_cents, name into v_policy, v_fee, v_name
  from public.communes where id = p_commune_id;
  if v_name is null then
    return jsonb_build_object('ok', false, 'message', 'Médiathèque introuvable.');
  end if;
  if v_policy = 'refuse' then
    return jsonb_build_object('ok', false, 'message', 'La médiathèque de ' || v_name || ' n''accueille pas les non-résidents pour le moment.');
  end if;

  select * into v_existing from public.memberships where user_id = auth.uid() and commune_id = p_commune_id;
  if v_existing.id is not null and v_existing.status in ('pending', 'active') then
    return jsonb_build_object('ok', false, 'message',
      case v_existing.status when 'pending' then 'Ta demande est déjà en attente de validation.' else 'Tu es déjà inscrit(e) dans cette médiathèque.' end);
  end if;

  insert into public.memberships (user_id, commune_id, status, fee_cents)
  values (auth.uid(), p_commune_id, 'pending', case when v_policy = 'paid' then v_fee else 0 end)
  on conflict (user_id, commune_id) do update set status = 'pending', fee_cents = excluded.fee_cents, created_at = now();

  return jsonb_build_object('ok', true, 'message',
    'Demande envoyée à la médiathèque de ' || v_name || '. ' ||
    case when v_policy = 'paid' and v_fee > 0
      then 'Présente-toi à l''accueil pour régler le supplément non-résident (' || to_char(v_fee / 100.0, 'FM999990.00') || ' €) et activer ton inscription.'
      else 'Elle sera activée par un agent, gratuitement.' end);
end;
$$;

create or replace function public.decide_membership(p_membership_id bigint, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.memberships;
  v_name text;
  v_expires timestamptz;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  select * into v_member from public.memberships where id = p_membership_id;
  if v_member.id is null then
    return jsonb_build_object('ok', false, 'message', 'Demande introuvable.');
  end if;
  if not public.is_super_admin() and v_member.commune_id is distinct from public.agent_commune_id() then
    raise exception 'Cette demande concerne une autre médiathèque.';
  end if;
  select name into v_name from public.communes where id = v_member.commune_id;

  if p_accept then
    v_expires := public.membership_expiry(v_member.commune_id, now());
    update public.memberships set status = 'active', expires_at = v_expires, validated_at = now(), validated_by = auth.uid()
      where id = p_membership_id;
    insert into public.notifications (user_id, message)
    values (v_member.user_id, 'Ton inscription à la médiathèque de ' || coalesce(v_name, '') || ' est validée : tu peux maintenant y emprunter et réserver.');
  else
    update public.memberships set status = 'refused', validated_at = now(), validated_by = auth.uid() where id = p_membership_id;
    insert into public.notifications (user_id, message)
    values (v_member.user_id, 'Ta demande d''inscription à la médiathèque de ' || coalesce(v_name, '') || ' n''a pas été acceptée. Renseigne-toi à l''accueil.');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- Réservations : bloquées si l'adhésion a expiré ou si l'usager n'est pas
-- inscrit dans la médiathèque où il veut récupérer le livre.
create or replace function public.check_reservation_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_commune bigint;
begin
  v_commune := coalesce(new.pickup_commune_id, (select commune_id from public.books where id = new.book_id));
  v_status := public.membership_status(new.user_id, v_commune);
  if v_status <> 'ok' then
    raise exception '%', public.membership_error_message(v_status);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_check_reservation_membership on public.reservations;
create trigger trg_check_reservation_membership
  before insert on public.reservations
  for each row execute function public.check_reservation_membership();


-- ============================================================
-- 3. Emprunt au comptoir : contrôle d'adhésion (remplace le seul contrôle
--    « prêt limité à sa commune » par la validité de l'inscription)
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
-- 4. Prolongation (+7 jours, une fois)
-- ============================================================
create or replace function public.renew_loan(p_loan_id bigint default null, p_reservation_id bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.loans;
  v_book_id bigint;
  v_new_due timestamptz;
begin
  if p_loan_id is not null then
    select * into v_loan from public.loans where id = p_loan_id and returned_at is null;
  else
    select * into v_loan from public.loans where reservation_id = p_reservation_id and returned_at is null;
  end if;

  if v_loan.id is null then
    return jsonb_build_object('ok', false, 'message', 'Prêt introuvable ou déjà rendu.');
  end if;
  if not (v_loan.user_id = auth.uid() or public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès refusé';
  end if;
  if v_loan.renewal_count >= 1 then
    return jsonb_build_object('ok', false, 'message', 'Ce prêt a déjà été prolongé une fois.');
  end if;
  if v_loan.due_at <= now() then
    return jsonb_build_object('ok', false, 'message', 'Ce prêt est en retard : il ne peut plus être prolongé, le livre est à rapporter.');
  end if;

  select book_id into v_book_id from public.book_copies where id = v_loan.copy_id;
  if exists (select 1 from public.holds where book_id = v_book_id and status = 'waiting') then
    return jsonb_build_object('ok', false, 'message', 'Quelqu''un attend ce livre : il ne peut pas être prolongé.');
  end if;

  v_new_due := v_loan.due_at + interval '7 days';
  update public.loans
    set due_at = v_new_due, renewal_count = renewal_count + 1, return_reminded = false, overdue_reminded = false
    where id = v_loan.id;
  if v_loan.reservation_id is not null then
    update public.reservations
      set return_due_at = v_new_due, return_reminded = false, overdue_reminded = false
      where id = v_loan.reservation_id;
  end if;

  return jsonb_build_object('ok', true, 'due_at', v_new_due,
    'message', 'Prêt prolongé : à rendre avant le ' || to_char(v_new_due, 'DD/MM/YYYY') || '.');
end;
$$;


-- ============================================================
-- 5. File d'attente
-- ============================================================
create table if not exists public.holds (
  id bigint generated always as identity primary key,
  book_id bigint not null references public.books(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'waiting' check (status in ('waiting', 'promoted', 'cancelled', 'skipped')),
  reservation_id bigint references public.reservations(id) on delete set null,
  created_at timestamptz not null default now(),
  promoted_at timestamptz
);

create unique index if not exists holds_one_waiting_per_user
  on public.holds (book_id, user_id) where status = 'waiting';
create index if not exists holds_waiting_idx on public.holds (book_id, created_at) where status = 'waiting';

alter table public.holds enable row level security;

drop policy if exists "Un usager voit ses files d'attente" on public.holds;
create policy "Un usager voit ses files d'attente"
  on public.holds for select
  using (auth.uid() = user_id or public.is_agent() or public.is_super_admin());

create or replace function public.join_hold(p_book_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_book public.books;
  v_status text;
  v_position integer;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;
  select * into v_book from public.books where id = p_book_id;
  if v_book.id is null then
    return jsonb_build_object('ok', false, 'message', 'Livre introuvable.');
  end if;
  if coalesce(v_book.on_site_only, false) then
    return jsonb_build_object('ok', false, 'message', 'Ce document se consulte uniquement sur place.');
  end if;
  if exists (select 1 from public.book_copies where book_id = p_book_id and status = 'available') then
    return jsonb_build_object('ok', false, 'message', 'Ce livre est disponible : tu peux le réserver directement.');
  end if;
  if exists (select 1 from public.reservations where book_id = p_book_id and user_id = auth.uid() and status in ('preparation', 'pret'))
    or exists (select 1 from public.loans l join public.book_copies c on c.id = l.copy_id
               where c.book_id = p_book_id and l.user_id = auth.uid() and l.returned_at is null) then
    return jsonb_build_object('ok', false, 'message', 'Tu as déjà ce livre en réservation ou en prêt.');
  end if;

  v_status := public.membership_status(auth.uid(), v_book.commune_id);
  if v_status <> 'ok' then
    return jsonb_build_object('ok', false, 'message', public.membership_error_message(v_status));
  end if;

  insert into public.holds (book_id, user_id) values (p_book_id, auth.uid())
  on conflict do nothing;

  select count(*) into v_position from public.holds
  where book_id = p_book_id and status = 'waiting'
    and created_at <= (select created_at from public.holds where book_id = p_book_id and user_id = auth.uid() and status = 'waiting');

  return jsonb_build_object('ok', true, 'position', v_position,
    'message', 'Tu es n° ' || v_position || ' dans la file d''attente. Tu seras prévenu(e) dès que le livre sera mis de côté pour toi.');
end;
$$;

create or replace function public.leave_hold(p_hold_id bigint)
returns void
language sql
security definer
set search_path = public
as $$
  update public.holds set status = 'cancelled'
  where id = p_hold_id and user_id = auth.uid() and status = 'waiting';
$$;

-- Mes files d'attente avec ma position (l'usager ne voit pas les autres lignes).
create or replace function public.my_holds()
returns table (hold_id bigint, book_id bigint, title text, author text, cover_url text, cover_initial text, queue_position bigint, created_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select h.id, b.id, b.title, b.author, b.cover_url, b.cover_initial,
    (select count(*) from public.holds h2 where h2.book_id = h.book_id and h2.status = 'waiting' and h2.created_at <= h.created_at),
    h.created_at
  from public.holds h
  join public.books b on b.id = h.book_id
  where h.user_id = auth.uid() and h.status = 'waiting'
  order by h.created_at;
$$;

-- Nombre de personnes qui attendent chaque livre (catalogue usager).
create or replace function public.hold_counts(p_book_ids bigint[])
returns table (book_id bigint, waiting bigint)
language sql
stable
security definer
set search_path = public
as $$
  select book_id, count(*) from public.holds
  where status = 'waiting' and book_id = any(p_book_ids)
  group by book_id;
$$;

-- Donne l'exemplaire p_copy_id au premier de la file : réservation créée et
-- passée tout de suite à « prête » (le livre est dans les mains de l'agent),
-- ce qui déclenche l'alerte et le délai de 48 h existants. Un usager qui ne
-- peut plus réserver (quota atteint, adhésion expirée…) est sauté.
-- Renvoie true si l'exemplaire a été attribué.
create or replace function public.promote_next_hold(p_copy_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_hold public.holds;
  v_reservation_id bigint;
  v_title text;
  v_email text;
  v_name text;
begin
  select * into v_copy from public.book_copies where id = p_copy_id;
  if v_copy.id is null then
    return false;
  end if;
  select title into v_title from public.books where id = v_copy.book_id;

  for v_hold in
    select * from public.holds where book_id = v_copy.book_id and status = 'waiting' order by created_at
  loop
    begin
      insert into public.reservations (user_id, book_id, status, pickup_commune_id)
      values (v_hold.user_id, v_copy.book_id, 'preparation', v_copy.current_commune_id)
      returning id into v_reservation_id;

      update public.book_copies set status = 'reserved' where id = v_copy.id;
      update public.reservations set status = 'pret' where id = v_reservation_id;
      update public.holds set status = 'promoted', reservation_id = v_reservation_id, promoted_at = now() where id = v_hold.id;

      select u.email, p.full_name into v_email, v_name
      from auth.users u left join public.profiles p on p.id = u.id where u.id = v_hold.user_id;
      if v_email is not null and to_regclass('public.email_outbox') is not null then
        insert into public.email_outbox (to_email, to_name, subject, body_text)
        values (v_email, v_name, 'Votre livre est arrivé : « ' || coalesce(v_title, '') || ' »',
          'Bonjour' || coalesce(' ' || v_name, '') || E',\n\nLe livre « ' || coalesce(v_title, '') ||
          E' » que vous attendiez est revenu : il est mis de côté pour vous à la médiathèque.\n' ||
          E'Vous avez 48 heures pour venir le chercher, passé ce délai il sera proposé à la personne suivante.\n\nÀ bientôt,\nVotre médiathèque');
      end if;
      return true;
    exception when others then
      update public.holds set status = 'skipped' where id = v_hold.id;
      insert into public.notifications (user_id, message)
      values (v_hold.user_id, '« ' || coalesce(v_title, '') || ' » que tu attendais est revenu, mais il n''a pas pu être mis de côté pour toi (' || sqlerrm || '). Il passe à la personne suivante.');
    end;
  end loop;
  return false;
end;
$$;

-- Déclenchement : un exemplaire redevient disponible (retour, fin de
-- transfert…) et quelqu'un l'attend. Nommé « zz_ » pour passer après les
-- autres triggers de book_copies (mise à jour de books.available).
create or replace function public.trg_promote_hold_on_available()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'available' and old.status is distinct from 'available'
    and exists (select 1 from public.holds where book_id = new.book_id and status = 'waiting') then
    perform public.promote_next_hold(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists zz_promote_hold_on_available on public.book_copies;
create trigger zz_promote_hold_on_available
  after update of status on public.book_copies
  for each row execute function public.trg_promote_hold_on_available();

-- Fin des 48 h sans retrait : la réservation expire, l'exemplaire mis de côté
-- passe au suivant de la file, sinon il redevient disponible. Appelée par le
-- back-office (remplace la simple mise à jour faite dans le navigateur).
create or replace function public.expire_reservation(p_reservation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reservation public.reservations;
  v_copy_id bigint;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  select * into v_reservation from public.reservations where id = p_reservation_id;
  if v_reservation.id is null or v_reservation.status <> 'pret' then
    return jsonb_build_object('ok', false);
  end if;

  update public.reservations set status = 'expiree', reshelved = false where id = p_reservation_id;

  select id into v_copy_id from public.book_copies
  where book_id = v_reservation.book_id and status = 'reserved'
    and current_commune_id = coalesce(v_reservation.pickup_commune_id, current_commune_id)
  order by id limit 1;

  if v_copy_id is not null then
    if not public.promote_next_hold(v_copy_id) then
      update public.book_copies set status = 'available' where id = v_copy_id;
    end if;
  end if;
  update public.books set available = exists (
    select 1 from public.book_copies where book_id = v_reservation.book_id and status = 'available'
  ) where id = v_reservation.book_id;
  return jsonb_build_object('ok', true);
end;
$$;


-- ============================================================
-- 6. Préparation d'une réservation : retrait dans la médiathèque choisie
--    (pickup_commune_id) plutôt que toujours celle de l'usager
-- ============================================================
create or replace function public.prepare_reservation(p_reservation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reservation public.reservations;
  v_user_commune bigint;
  v_copy public.book_copies;
  v_here bigint;
  v_dest_name text;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_reservation from public.reservations where id = p_reservation_id;
  if v_reservation.id is null then
    return jsonb_build_object('ok', false, 'message', 'Réservation introuvable.');
  end if;
  if v_reservation.status <> 'preparation' then
    return jsonb_build_object('ok', false, 'message', 'Cette réservation n''est plus en préparation.');
  end if;

  select commune_id into v_user_commune from public.profiles where id = v_reservation.user_id;
  v_here := coalesce(v_reservation.pickup_commune_id, v_user_commune, public.agent_commune_id());

  select c.* into v_copy
  from public.book_copies c
  where c.book_id = v_reservation.book_id and c.status = 'available'
  order by (c.current_commune_id = v_here) desc, c.id
  limit 1;

  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun exemplaire disponible pour ce livre en ce moment, dans aucune médiathèque du réseau.');
  end if;

  if v_copy.current_commune_id = v_here then
    update public.reservations set status = 'pret' where id = p_reservation_id;
    return jsonb_build_object('ok', true, 'needs_transfer', false, 'message', 'Réservation prête à récupérer.');
  end if;

  update public.book_copies set status = 'reserved' where id = v_copy.id;

  insert into public.transfers (copy_id, from_commune_id, to_commune_id, status, requested_by, reservation_id, notes)
  values (v_copy.id, v_copy.current_commune_id, v_here, 'requested', auth.uid(), p_reservation_id, 'Demandé pour une réservation en préparation');

  select name into v_dest_name from public.communes where id = v_copy.current_commune_id;

  return jsonb_build_object(
    'ok', true,
    'needs_transfer', true,
    'message', 'Aucun exemplaire ici : transfert demandé depuis ' || coalesce(v_dest_name, 'une autre médiathèque') || '. L''usager sera prévenu à l''arrivée.'
  );
end;
$$;


-- ============================================================
-- 7. Rappel d'adhésion 30 jours avant l'échéance (cron quotidien)
-- ============================================================
create or replace function public.queue_membership_reminders()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select p.id, p.full_name, p.membership_expires_at, u.email
    from public.profiles p join auth.users u on u.id = p.id
    where p.membership_expires_at is not null
      and p.membership_expires_at between now() and now() + interval '30 days'
      and p.membership_reminded_at is null
  loop
    insert into public.notifications (user_id, message)
    values (r.id, 'Ton adhésion à la médiathèque expire le ' || to_char(r.membership_expires_at, 'DD/MM/YYYY') || ' : pense à la renouveler à l''accueil.');
    if r.email is not null and to_regclass('public.email_outbox') is not null then
      insert into public.email_outbox (to_email, to_name, subject, body_text)
      values (r.email, r.full_name, 'Votre adhésion à la médiathèque arrive à échéance',
        'Bonjour' || coalesce(' ' || r.full_name, '') || E',\n\nVotre adhésion expire le ' || to_char(r.membership_expires_at, 'DD/MM/YYYY') ||
        E'. Pensez à la renouveler à l''accueil de la médiathèque pour continuer à emprunter.\n\nÀ bientôt,\nVotre médiathèque');
    end if;
    update public.profiles set membership_reminded_at = now() where id = r.id;
  end loop;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'queue-membership-reminders';
    perform cron.schedule('queue-membership-reminders', '20 9 * * *', 'select public.queue_membership_reminders()');
  end if;
end $$;

grant execute on function public.renew_loan(bigint, bigint) to authenticated;
grant execute on function public.join_hold(bigint) to authenticated;
grant execute on function public.leave_hold(bigint) to authenticated;
grant execute on function public.my_holds() to authenticated;
grant execute on function public.hold_counts(bigint[]) to anon, authenticated;
grant execute on function public.request_membership(bigint) to authenticated;
grant execute on function public.decide_membership(bigint, boolean) to authenticated;
grant execute on function public.renew_membership(uuid, bigint) to authenticated;
grant execute on function public.expire_reservation(bigint) to authenticated;
grant execute on function public.membership_status(uuid, bigint) to authenticated;
grant execute on function public.update_commune_membership_settings(bigint, text, text, integer) to authenticated;
