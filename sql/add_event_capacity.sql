-- BliGO — Nombre de places limité sur un événement (14/09/2026)
-- max_seats vide = illimité (utile pour un événement en extérieur, sans jauge).
-- Sinon, un nombre positif : l'inscription est bloquée une fois la jauge atteinte.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

alter table public.events add column if not exists max_seats integer;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'events_max_seats_positive'
  ) then
    alter table public.events
      add constraint events_max_seats_positive check (max_seats is null or max_seats > 0);
  end if;
end $$;

-- Bloque l'inscription dès que la jauge est atteinte. Vérifié côté base (pas
-- seulement côté appli) pour rester fiable même si deux usagers s'inscrivent
-- au même moment sur les dernières places.
create or replace function public.enforce_event_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max integer;
  v_count integer;
begin
  select max_seats into v_max from public.events where id = new.event_id;

  if v_max is not null then
    select count(*) into v_count from public.event_rsvps where event_id = new.event_id;
    if v_count >= v_max then
      raise exception 'Cet événement affiche complet.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_event_capacity on public.event_rsvps;

create trigger trg_enforce_event_capacity
  before insert on public.event_rsvps
  for each row execute function public.enforce_event_capacity();
