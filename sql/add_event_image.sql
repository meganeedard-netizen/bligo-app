-- BliGO — Affiche/photo d'un événement de l'agenda culturel (16/09/2026)
--
-- Beaucoup d'événements ont une vraie affiche (papier, réseaux sociaux) —
-- Mégane veut pouvoir la déposer et que l'usager la voie en ouvrant la fiche
-- de l'événement. Même principe que les couvertures de livres : un bucket de
-- stockage public en lecture, écriture réservée à la direction (cohérent
-- avec les policies sur `events` elles-mêmes, voir add_agent_roles_tariffs_and_age.sql).
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

alter table public.events add column if not exists image_url text;
comment on column public.events.image_url is 'Affiche/photo de l''événement, affichée dans la fiche détaillée côté usager.';

-- Si cet insert est refusé par l'éditeur SQL de ton projet Supabase (rare, selon le plan),
-- crée le bucket à la main : Dashboard > Storage > New bucket > nom "event-images" > Public ON,
-- puis exécute seulement les 3 "create policy" ci-dessous.
insert into storage.buckets (id, name, public)
values ('event-images', 'event-images', true)
on conflict (id) do nothing;

create policy "Lecture publique des affiches d'événements"
  on storage.objects for select
  using (bucket_id = 'event-images');

create policy "La direction dépose des affiches d'événements"
  on storage.objects for insert
  with check (bucket_id = 'event-images' and public.is_direction());

create policy "La direction remplace des affiches d'événements"
  on storage.objects for update
  using (bucket_id = 'event-images' and public.is_direction())
  with check (bucket_id = 'event-images' and public.is_direction());
