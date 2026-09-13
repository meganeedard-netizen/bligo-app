-- Points de fidélité automatiques + Agenda culturel (remplace l'idée de "communauté" /
-- classement entre usagers, volontairement absent).

-- 0. Objectif de lecture annuel (modifiable par chaque usager)
alter table public.profiles add column if not exists reading_goal integer not null default 12;

-- 1. Points automatiques quand une réservation est récupérée
create or replace function public.award_points_on_pickup()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.status = 'recupere' and old.status is distinct from 'recupere' then
    update public.profiles set loyalty_points = loyalty_points + 10 where id = new.user_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_award_points_on_pickup on public.reservations;
create trigger trg_award_points_on_pickup
  after update on public.reservations
  for each row execute procedure public.award_points_on_pickup();

-- 2. Points automatiques + suivi de l'emprunteur sur la Bibliothèque Libre
alter table public.free_books add column if not exists borrowed_by uuid references auth.users(id);

create or replace function public.borrow_free_book(p_book_id bigint)
returns boolean
language plpgsql
security definer
as $$
declare
  affected int;
begin
  update public.free_books
  set available = false, borrowed_by = auth.uid()
  where id = p_book_id and available = true;
  get diagnostics affected = row_count;
  if affected > 0 then
    update public.profiles set loyalty_points = loyalty_points + 5 where id = auth.uid();
  end if;
  return affected > 0;
end;
$$;

-- 3. Agenda culturel
create table public.events (
  id bigint generated always as identity primary key,
  commune_id bigint references public.communes(id),
  title text not null,
  description text,
  event_date timestamptz not null,
  location text,
  created_at timestamptz not null default now()
);

alter table public.events enable row level security;

create policy "Les événements sont publics en lecture"
  on public.events for select
  using (true);

create table public.event_rsvps (
  id bigint generated always as identity primary key,
  event_id bigint not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (event_id, user_id)
);

alter table public.event_rsvps enable row level security;

create policy "Les inscriptions sont publiques en lecture"
  on public.event_rsvps for select
  using (true);

create policy "Un usager s'inscrit lui-même"
  on public.event_rsvps for insert
  with check (auth.uid() = user_id);

create policy "Un usager se désinscrit lui-même"
  on public.event_rsvps for delete
  using (auth.uid() = user_id);

-- Points automatiques à l'inscription à un événement
create or replace function public.award_points_on_rsvp()
returns trigger
language plpgsql
security definer
as $$
begin
  update public.profiles set loyalty_points = loyalty_points + 5 where id = new.user_id;
  return new;
end;
$$;

drop trigger if exists trg_award_points_on_rsvp on public.event_rsvps;
create trigger trg_award_points_on_rsvp
  after insert on public.event_rsvps
  for each row execute procedure public.award_points_on_rsvp();

insert into public.events (commune_id, title, description, event_date, location) values
  ((select id from public.communes where name = 'Val-Fleuri'), 'Club de lecture', 'Discussion autour de « Texaco » de Patrick Chamoiseau, animée par l''équipe de la médiathèque.', '2026-09-04 18:00:00+00', 'Médiathèque de Val-Fleuri'),
  ((select id from public.communes where name = 'Val-Fleuri'), 'Atelier d''écriture', 'Un atelier ouvert à tous pour découvrir l''écriture créole et créative.', '2026-09-11 17:00:00+00', 'Médiathèque de Val-Fleuri'),
  ((select id from public.communes where name = 'Le Moule'), 'Heure du conte', 'Séance de lecture pour les enfants de 4 à 8 ans.', '2026-09-06 10:30:00+00', 'Médiathèque du Moule');
