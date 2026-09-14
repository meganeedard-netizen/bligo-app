-- BliGO — Corrige l'ajout d'événement par l'administratrice + durée de l'événement (14/09/2026)
--
-- 1. Les policies d'écriture sur `events` (add_agenda_admin.sql) ne vérifiaient
--    que is_agent(), jamais is_super_admin() — un compte super_admin (comme
--    celui de Mégane) se voyait donc refuser l'ajout d'un événement par la
--    RLS ("new row violates row-level security policy for table events").
-- 2. Ajoute une durée à l'événement (en minutes), pour remplacer les 90 minutes
--    fixes utilisées jusqu'ici dans l'export .ics de l'agenda usager.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

drop policy if exists "Un agent ajoute des événements" on public.events;
drop policy if exists "Un agent modifie les événements" on public.events;
drop policy if exists "Un agent supprime des événements" on public.events;

create policy "Un agent ou l'administratrice ajoute des événements"
  on public.events for insert
  with check (public.is_agent() or public.is_super_admin());

create policy "Un agent ou l'administratrice modifie les événements"
  on public.events for update
  using (public.is_agent() or public.is_super_admin());

create policy "Un agent ou l'administratrice supprime des événements"
  on public.events for delete
  using (public.is_agent() or public.is_super_admin());

alter table public.events add column if not exists duration_minutes integer not null default 90;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'events_duration_positive'
  ) then
    alter table public.events
      add constraint events_duration_positive check (duration_minutes > 0);
  end if;
end $$;
