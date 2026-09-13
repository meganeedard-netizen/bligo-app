-- À exécuter dans Supabase (SQL Editor > New query > coller > Run)
-- Ajoute la date de mise à disposition d'une réservation (pour le décompte 48h) et
-- un statut "expiree" pour les réservations prêtes non récupérées à temps.

alter table public.reservations add column if not exists ready_at timestamptz;

-- Reste à false tant que l'agent n'a pas confirmé avoir physiquement remis le
-- livre en rayon (checklist persistante dans l'onglet dédié du back-office).
alter table public.reservations add column if not exists reshelved boolean not null default true;

alter table public.reservations drop constraint if exists reservations_status_check;
alter table public.reservations add constraint reservations_status_check
  check (status in ('preparation', 'pret', 'recupere', 'expiree'));
