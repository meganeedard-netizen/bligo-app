-- BliGO, améliorations du 23/11/2026 (retours Landerneau + Les Abymes)
-- 1. Qui a catalogué quoi (visible des agents seulement)
-- 2. Catalogage ouvert à tous les agents (demande de Mégane : tout ouvert avant le 1er contrat)
-- 3. Ressources numériques : statut, échéance, adhérents, nombre d'ouvertures
-- 4. Événements payants et suivi des encaissements (préparation PayFiP)
-- Additif, relançable.

-- ============ 1. Auteur du catalogage ============
create table if not exists public.book_catalogers (
  book_id bigint primary key references public.books(id) on delete cascade,
  agent_id uuid references auth.users(id) on delete set null,
  lot text,
  created_at timestamptz not null default now()
);
alter table public.book_catalogers enable row level security;
drop policy if exists "Les agents voient qui a catalogué" on public.book_catalogers;
create policy "Les agents voient qui a catalogué" on public.book_catalogers for select using (public.is_agent());

create or replace function public.trg_set_book_cataloger() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    insert into public.book_catalogers (book_id, agent_id) values (new.id, auth.uid()) on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists trg_books_cataloger on public.books;
create trigger trg_books_cataloger after insert on public.books for each row execute function public.trg_set_book_cataloger();

insert into public.book_catalogers (book_id, agent_id, created_at)
select distinct on (b.id) b.id, a.actor_id, a.occurred_at from public.activity_events a
  join public.books b on b.id::text = a.entity_id
 where a.event_type = 'book_created' and a.actor_id is not null order by b.id, a.occurred_at
on conflict do nothing;

create or replace function public.set_book_lot(p_book_id bigint, p_lot text) returns void
language sql security definer set search_path = public as $$
  update public.book_catalogers set lot = nullif(trim(p_lot), '') where book_id = p_book_id and agent_id = auth.uid();
$$;
revoke all on function public.set_book_lot(bigint, text) from public, anon;
grant execute on function public.set_book_lot(bigint, text) to authenticated;

create or replace function public.book_cataloger(p_book_id bigint)
returns table (agent_name text, lot text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select coalesce(p.full_name, 'Agent'), c.lot, c.created_at from public.book_catalogers c
    left join public.profiles p on p.id = c.agent_id
   where c.book_id = p_book_id and public.is_agent();
$$;
revoke all on function public.book_cataloger(bigint) from public, anon;
grant execute on function public.book_cataloger(bigint) to authenticated;

create or replace function public.rename_catalog_lot(p_old text, p_new text) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.is_agent() then raise exception 'Réservé aux agents.'; end if;
  if coalesce(trim(p_new), '') = '' then raise exception 'Indique un nom de panier.'; end if;
  update public.catalog_drafts set lot = trim(p_new), updated_at = now() where agent_id = auth.uid() and lot is not distinct from p_old;
  get diagnostics n = row_count; return n;
end $$;
revoke all on function public.rename_catalog_lot(text, text) from public, anon;
grant execute on function public.rename_catalog_lot(text, text) to authenticated;

-- ============ 2. Catalogage ouvert aux agents ============
drop policy if exists "Les agents ajoutent des livres" on public.books;
create policy "Les agents ajoutent des livres" on public.books for insert with check (public.is_agent());
drop policy if exists "Les agents modifient les livres" on public.books;
create policy "Les agents modifient les livres" on public.books for update using (public.is_agent());

-- ============ 3. Ressources numériques ============
alter table public.digital_resources add column if not exists active boolean not null default true;
alter table public.digital_resources add column if not exists expires_on date;
alter table public.digital_resources add column if not exists members_only boolean not null default false;
-- Compteur par jour, sans aucune donnée sur l'usager (RGPD).
create table if not exists public.digital_resource_opens (
  resource_id bigint not null references public.digital_resources(id) on delete cascade,
  day date not null default current_date,
  opens integer not null default 0,
  primary key (resource_id, day)
);
alter table public.digital_resource_opens enable row level security;
drop policy if exists "Les agents voient les ouvertures" on public.digital_resource_opens;
create policy "Les agents voient les ouvertures" on public.digital_resource_opens for select using (public.is_agent());
create or replace function public.count_digital_open(p_resource_id bigint) returns void
language sql security definer set search_path = public as $$
  insert into public.digital_resource_opens as o (resource_id, opens)
  select id, 1 from public.digital_resources where id = p_resource_id
  on conflict (resource_id, day) do update set opens = o.opens + 1;
$$;
grant execute on function public.count_digital_open(bigint) to authenticated;
revoke execute on function public.count_digital_open(bigint) from public, anon;

-- ============ 4. Événements payants, encaissements ============
alter table public.events add column if not exists price_cents integer not null default 0;
create table if not exists public.payments (
  id bigint generated always as identity primary key,
  commune_id bigint not null references public.communes(id),
  user_id uuid references auth.users(id) on delete set null,
  kind text not null check (kind in ('adhesion', 'evenement')),
  event_id bigint references public.events(id) on delete set null,
  rsvp_id bigint unique,
  label text not null,
  payer_name text,
  amount_cents integer not null check (amount_cents >= 0),
  status text not null default 'a_regler' check (status in ('a_regler', 'paye', 'annule', 'a_rembourser', 'rembourse')),
  method text check (method in ('especes', 'carte', 'cheque', 'virement', 'payfip', 'gratuit')),
  reference text,
  recorded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index if not exists payments_commune_idx on public.payments (commune_id, created_at);
alter table public.payments enable row level security;
drop policy if exists "Un usager voit ses paiements" on public.payments;
create policy "Un usager voit ses paiements" on public.payments for select using (auth.uid() = user_id);
drop policy if exists "Les agents voient les paiements de leur médiathèque" on public.payments;
create policy "Les agents voient les paiements de leur médiathèque" on public.payments for select
  using (public.is_super_admin() or (public.is_agent() and commune_id = public.agent_commune_id()));

create or replace function public.trg_event_payment() returns trigger
language plpgsql security definer set search_path = public as $$
declare e public.events;
begin
  if tg_op = 'INSERT' then
    select * into e from public.events where id = new.event_id;
    if coalesce(e.price_cents, 0) > 0 and e.commune_id is not null then
      insert into public.payments (commune_id, user_id, kind, event_id, rsvp_id, label, amount_cents)
      values (e.commune_id, new.user_id, 'evenement', e.id, new.id, e.title, e.price_cents) on conflict do nothing;
    end if;
    return new;
  end if;
  update public.payments set status = case when status = 'paye' and amount_cents > 0 then 'a_rembourser' else 'annule' end
   where rsvp_id = old.id and status in ('a_regler', 'paye');
  return old;
end $$;
drop trigger if exists trg_event_rsvps_payment on public.event_rsvps;
create trigger trg_event_rsvps_payment after insert or delete on public.event_rsvps
  for each row execute function public.trg_event_payment();

create or replace function public.list_payments(p_from date, p_to date)
returns table (id bigint, kind text, label text, payer text, event_id bigint, rsvp_id bigint, amount_cents integer,
  status text, method text, reference text, agent_name text, created_at timestamptz, paid_at timestamptz)
language sql stable security definer set search_path = public as $$
  select y.id, y.kind, y.label, coalesce(p.full_name, y.payer_name, g.guest_name, 'Usager'), y.event_id, y.rsvp_id, y.amount_cents,
    y.status, y.method, y.reference, a.full_name, y.created_at, y.paid_at
  from public.payments y
  left join public.profiles p on p.id = y.user_id
  left join public.event_rsvp_guests g on g.rsvp_id = y.rsvp_id
  left join public.profiles a on a.id = y.recorded_by
  where public.is_agent() and y.commune_id = public.agent_commune_id()
    and (coalesce(y.paid_at, y.created_at) at time zone coalesce((select c.timezone from public.communes c where c.id = y.commune_id), 'Europe/Paris'))::date between p_from and p_to
  order by coalesce(y.paid_at, y.created_at) desc;
$$;
create or replace function public.settle_payment(p_id bigint, p_status text, p_method text default null, p_amount_cents integer default null, p_reference text default null)
returns void language plpgsql security definer set search_path = public as $$
declare y public.payments;
begin
  if not public.is_agent() then raise exception 'Réservé aux agents.'; end if;
  select * into y from public.payments where id = p_id and (commune_id = public.agent_commune_id() or public.is_super_admin()) for update;
  if y.id is null then raise exception 'Paiement introuvable.'; end if;
  if not ((y.status = 'a_regler' and p_status in ('paye', 'annule'))
       or (y.status = 'paye' and p_status = 'a_rembourser')
       or (y.status = 'a_rembourser' and p_status = 'rembourse')) then
    raise exception 'Ce paiement a déjà été traité.';
  end if;
  if p_status = 'paye' and p_method is null then raise exception 'Choisis le moyen de paiement.'; end if;
  update public.payments set status = p_status,
    method = coalesce(p_method, method),
    amount_cents = case when p_status <> 'paye' then amount_cents when p_method = 'gratuit' then 0 else coalesce(p_amount_cents, amount_cents) end,
    reference = coalesce(nullif(trim(p_reference), ''), reference),
    paid_at = case when p_status = 'paye' then now() else paid_at end,
    recorded_by = auth.uid()
  where id = p_id;
end $$;
create or replace function public.add_membership_payment(p_user_id uuid, p_amount_cents integer, p_method text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_agent() then raise exception 'Réservé aux agents.'; end if;
  insert into public.payments (commune_id, user_id, kind, label, amount_cents, status, method, recorded_by, paid_at)
  values (public.agent_commune_id(), p_user_id, 'adhesion', 'Adhésion annuelle', p_amount_cents, 'paye', p_method, auth.uid(), now());
end $$;
revoke all on function public.list_payments(date, date) from public, anon;
revoke all on function public.settle_payment(bigint, text, text, integer, text) from public, anon;
revoke all on function public.add_membership_payment(uuid, integer, text) from public, anon;
grant execute on function public.list_payments(date, date), public.settle_payment(bigint, text, text, integer, text),
  public.add_membership_payment(uuid, integer, text) to authenticated;

-- ============ 5. Place gardée pendant le règlement ============
alter table public.events add column if not exists payment_hold_hours integer;
alter table public.payments add column if not exists due_at timestamptz;
create or replace function public.trg_event_payment() returns trigger
language plpgsql security definer set search_path = public as $$
declare e public.events;
begin
  if tg_op = 'INSERT' then
    select * into e from public.events where id = new.event_id;
    if coalesce(e.price_cents, 0) > 0 and e.commune_id is not null then
      insert into public.payments (commune_id, user_id, kind, event_id, rsvp_id, label, amount_cents, due_at)
      values (e.commune_id, new.user_id, 'evenement', e.id, new.id, e.title, e.price_cents,
        case when e.payment_hold_hours is not null then least(now() + make_interval(hours => e.payment_hold_hours), e.event_date) end)
      on conflict do nothing;
    end if;
    return new;
  end if;
  update public.payments set status = case when status = 'paye' and amount_cents > 0 then 'a_rembourser' else 'annule' end
   where rsvp_id = old.id and status in ('a_regler', 'paye');
  return old;
end $$;
-- Le nom d'un inscrit sans compte est gardé sur le paiement (état de régie complet même après désinscription).
create or replace function public.trg_guest_payment_name() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.payments set payer_name = new.guest_name where rsvp_id = new.rsvp_id;
  return new;
end $$;
drop trigger if exists trg_rsvp_guest_payment_name on public.event_rsvp_guests;
create trigger trg_rsvp_guest_payment_name after insert on public.event_rsvp_guests
  for each row execute function public.trg_guest_payment_name();
-- Places non réglées dans le délai : libérées toutes les 15 minutes, avec un message à l'usager.
create or replace function public.release_unpaid_seats() returns integer
language plpgsql security definer set search_path = public as $$
declare y record; n integer := 0;
begin
  for y in select * from public.payments where status = 'a_regler' and due_at is not null and due_at < now() and rsvp_id is not null for update skip locked loop
    delete from public.event_rsvps where id = y.rsvp_id;
    if y.user_id is not null then
      insert into public.notifications (user_id, message)
      values (y.user_id, 'Ta place pour « ' || y.label || ' » a été libérée : le règlement n''a pas été fait dans le délai. Tu peux te réinscrire s''il reste des places.');
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.release_unpaid_seats() from public, anon, authenticated;
select cron.schedule('release-unpaid-seats', '*/15 * * * *', 'select public.release_unpaid_seats();');
