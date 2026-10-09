-- Carte famille et ressources numériques (09/10/2026)
-- ============================================================
-- Décisions de Mégane le 09/10/2026 :
--   Carte famille : un titulaire adulte porte l'abonnement (un paiement, une
--   échéance d'adhésion pour toute la famille). Chaque membre garde sa carte
--   et son numéro d'abonné (on sait qui emprunte quoi, restrictions mineurs
--   appliquées), les quotas sont partagés. Les enfants n'ont pas de compte :
--   ils sont gérés par le parent (profiles.managed_by), qui voit et réserve
--   pour eux. Un ado peut avoir son propre compte rattaché à la famille.
--   À l'inscription, l'usager déclare Adulte / Mineur / Famille.
--   Ressources numériques : liens vers les services de la médiathèque
--   (livres numériques, presse en ligne…), gérés par la direction, affichés
--   dans le profil usager.
-- À exécuter APRÈS add_renewal_holds_membership.sql.


-- ============================================================
-- 1. Réglages famille par médiathèque
-- ============================================================
alter table public.communes add column if not exists tariff_famille_cents integer not null default 0;
alter table public.communes add column if not exists family_max_loans integer not null default 15;
alter table public.communes add column if not exists family_max_members integer not null default 6;

create or replace function public.update_commune_family_settings(
  p_commune_id bigint, p_tariff_cents integer, p_max_loans integer, p_max_members integer
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
    set tariff_famille_cents = greatest(0, coalesce(p_tariff_cents, 0)),
        family_max_loans = greatest(1, coalesce(p_max_loans, 15)),
        family_max_members = greatest(2, coalesce(p_max_members, 6))
    where id = p_commune_id;
end;
$$;


-- ============================================================
-- 2. Familles
-- ============================================================
create table if not exists public.families (
  id bigint generated always as identity primary key,
  holder_id uuid not null unique references auth.users(id) on delete cascade,
  commune_id bigint references public.communes(id),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

alter table public.profiles add column if not exists family_id bigint references public.families(id) on delete set null;
alter table public.profiles add column if not exists managed_by uuid references auth.users(id) on delete set null;
alter table public.profiles add column if not exists wants_family boolean not null default false;

alter table public.families enable row level security;
drop policy if exists "Les membres et les agents voient la famille" on public.families;
create policy "Les membres et les agents voient la famille"
  on public.families for select
  using (public.is_agent() or public.is_super_admin()
    or id = (select family_id from public.profiles where id = auth.uid()));

-- Le parent voit la fiche, les prêts et les réservations de ses enfants.
drop policy if exists "Le parent voit ses enfants" on public.profiles;
create policy "Le parent voit ses enfants"
  on public.profiles for select
  using (managed_by = auth.uid());

drop policy if exists "Le parent voit les prêts de ses enfants" on public.loans;
create policy "Le parent voit les prêts de ses enfants"
  on public.loans for select
  using (user_id in (select id from public.profiles where managed_by = auth.uid()));

drop policy if exists "Le parent voit les réservations de ses enfants" on public.reservations;
create policy "Le parent voit les réservations de ses enfants"
  on public.reservations for select
  using (user_id in (select id from public.profiles where managed_by = auth.uid()));

-- Documents en cours pour toute la famille (prêts non rendus + réservations
-- actives) et quota de la médiathèque du titulaire.
create or replace function public.family_usage(p_family_id bigint)
returns table (used bigint, max_loans integer)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*) from public.loans l join public.profiles p on p.id = l.user_id
       where p.family_id = p_family_id and l.returned_at is null)
    + (select count(*) from public.reservations r join public.profiles p on p.id = r.user_id
       where p.family_id = p_family_id and r.status in ('preparation', 'pret')),
    (select coalesce(c.family_max_loans, 15) from public.families f left join public.communes c on c.id = f.commune_id where f.id = p_family_id);
$$;

create or replace function public.family_quota_reached(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select u.used >= u.max_loans
    from public.profiles p, lateral public.family_usage(p.family_id) u
    where p.id = p_user_id and p.family_id is not null), false);
$$;

create or replace function public.create_family(p_holder_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_holder public.profiles;
  v_family_id bigint;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  select * into v_holder from public.profiles where id = p_holder_id;
  if v_holder.id is null then
    return jsonb_build_object('ok', false, 'message', 'Usager introuvable.');
  end if;
  if v_holder.family_id is not null then
    return jsonb_build_object('ok', false, 'message', 'Cet usager fait déjà partie d''une famille.');
  end if;
  if v_holder.tariff_category = 'mineur' then
    return jsonb_build_object('ok', false, 'message', 'Le titulaire d''une carte famille doit être majeur.');
  end if;
  insert into public.families (holder_id, commune_id, created_by) values (p_holder_id, v_holder.commune_id, auth.uid())
  returning id into v_family_id;
  update public.profiles set family_id = v_family_id, wants_family = false where id = p_holder_id;
  insert into public.notifications (user_id, message)
  values (p_holder_id, 'Ta carte famille est active : ajoute tes enfants depuis ton profil, ou demande à l''accueil.');
  return jsonb_build_object('ok', true, 'family_id', v_family_id);
end;
$$;

-- Rattacher un compte existant (ex. un ado qui a sa propre appli).
create or replace function public.add_family_member(p_family_id bigint, p_subscriber_number text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.profiles;
  v_count integer;
  v_max integer;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  select * into v_member from public.profiles where subscriber_number = trim(p_subscriber_number);
  if v_member.id is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun usager ne porte ce numéro d''abonné.');
  end if;
  if v_member.family_id is not null then
    return jsonb_build_object('ok', false, 'message', 'Cet usager fait déjà partie d''une famille.');
  end if;
  select count(*) into v_count from public.profiles where family_id = p_family_id;
  select coalesce(c.family_max_members, 6) into v_max from public.families f left join public.communes c on c.id = f.commune_id where f.id = p_family_id;
  if v_count >= v_max then
    return jsonb_build_object('ok', false, 'message', 'La carte famille compte déjà ' || v_max || ' membres (maximum de la médiathèque).');
  end if;
  update public.profiles set family_id = p_family_id where id = v_member.id;
  return jsonb_build_object('ok', true, 'message', v_member.full_name || ' a rejoint la carte famille.');
end;
$$;

-- Retirer un membre ; retirer le titulaire dissout la famille.
create or replace function public.remove_family_member(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_family public.families;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  select f.* into v_family from public.families f join public.profiles p on p.family_id = f.id where p.id = p_user_id;
  if v_family.id is null then
    return jsonb_build_object('ok', false, 'message', 'Cet usager ne fait partie d''aucune famille.');
  end if;
  if v_family.holder_id = p_user_id then
    update public.profiles set family_id = null where family_id = v_family.id;
    delete from public.families where id = v_family.id;
    return jsonb_build_object('ok', true, 'message', 'Carte famille dissoute : chaque membre redevient individuel.');
  end if;
  update public.profiles set family_id = null where id = p_user_id;
  return jsonb_build_object('ok', true, 'message', 'Membre retiré de la carte famille.');
end;
$$;

-- Catégorie déclarée par l'usager en préinscription (non vérifiée : l'agent
-- confirme à la validation). « famille » = majeur qui souhaite une carte famille.
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
  update public.profiles
    set tariff_category = case when p_category = 'mineur' then 'mineur' else 'majeur' end,
        wants_family = (p_category = 'famille')
    where id = auth.uid() and coalesce(registration_status, 'pre_inscrit') <> 'valide';
end;
$$;

-- Le parent réserve pour un enfant qu'il gère.
create or replace function public.reserve_for_member(p_book_id bigint, p_member_id uuid, p_pickup_commune_id bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.profiles where id = p_member_id and managed_by = auth.uid()) then
    raise exception 'Tu ne peux réserver que pour les enfants de ta carte famille.';
  end if;
  insert into public.reservations (user_id, book_id, status, pickup_commune_id)
  values (p_member_id, p_book_id, 'preparation', p_pickup_commune_id);
  return jsonb_build_object('ok', true);
end;
$$;


-- ============================================================
-- 3. Adhésion et quotas partagés (reprennent les versions du 09/10)
-- ============================================================
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
  -- Carte famille : l'adhésion est celle du titulaire, pour tous les membres.
  select coalesce(h.membership_expires_at, v_expires) into v_expires
  from public.profiles p join public.families f on f.id = p.family_id join public.profiles h on h.id = f.holder_id
  where p.id = p_user_id and h.id <> p.id;
  v_expires := coalesce(v_expires, (select membership_expires_at from public.profiles where id = p_user_id));

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
  if public.family_quota_reached(new.user_id) then
    raise exception 'Le quota de la carte famille est atteint : un document doit être rendu avant une nouvelle réservation.';
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

  if public.family_quota_reached(v_user_id) then
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
  if not (v_loan.user_id = auth.uid() or public.is_agent() or public.is_super_admin()
    or exists (select 1 from public.profiles where id = v_loan.user_id and managed_by = auth.uid())) then
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
-- 4. Ressources numériques
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

grant execute on function public.update_commune_family_settings(bigint, integer, integer, integer) to authenticated;
grant execute on function public.family_usage(bigint) to authenticated;
grant execute on function public.create_family(uuid) to authenticated;
grant execute on function public.add_family_member(bigint, text) to authenticated;
grant execute on function public.remove_family_member(uuid) to authenticated;
grant execute on function public.declare_my_category(text) to authenticated;
grant execute on function public.reserve_for_member(bigint, uuid, bigint) to authenticated;
