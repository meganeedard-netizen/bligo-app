-- BliGO — Corrige l'erreur "Could not find the 'duration_minutes' column" (16/09/2026)
--
-- sql/fix_events_super_admin_and_duration.sql (écrit le 14/09/2026) n'avait
-- jamais été exécuté : la colonne duration_minutes n'existe donc pas encore
-- sur `events`, d'où l'erreur au moment de créer un événement.
--
-- Ce fichier fait la même chose que ce vieux fichier pour la colonne, MAIS
-- nettoie aussi les anciennes policies d'écriture sur `events` : depuis
-- sql/add_agent_roles_tariffs_and_age.sql (point 9, exécuté aujourd'hui),
-- seules les policies "La direction ajoute/modifie/supprime des événements"
-- doivent exister (un compte agent restreint ne doit plus pouvoir toucher à
-- l'agenda). Si l'ancien fichier venait à être exécuté après coup, ses
-- policies "Un agent ou l'administratrice ..." rouvriraient l'accès à tous
-- les agents — ce fichier les supprime pour ne garder que les bonnes.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

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

-- Nettoyage : ne garder que les policies basées sur is_direction().
drop policy if exists "Un agent ajoute des événements" on public.events;
drop policy if exists "Un agent modifie les événements" on public.events;
drop policy if exists "Un agent supprime des événements" on public.events;
drop policy if exists "Un agent ou l'administratrice ajoute des événements" on public.events;
drop policy if exists "Un agent ou l'administratrice modifie les événements" on public.events;
drop policy if exists "Un agent ou l'administratrice supprime des événements" on public.events;

drop policy if exists "La direction ajoute des événements" on public.events;
drop policy if exists "La direction modifie les événements" on public.events;
drop policy if exists "La direction supprime des événements" on public.events;

create policy "La direction ajoute des événements"
  on public.events for insert
  with check (public.is_direction());

create policy "La direction modifie les événements"
  on public.events for update
  using (public.is_direction());

create policy "La direction supprime des événements"
  on public.events for delete
  using (public.is_direction());
