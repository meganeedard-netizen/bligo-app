-- Préférences de lecture (posées une fois à l'inscription) + objectif de
-- lecture mensuel, utilisés pour personnaliser les recommandations affichées
-- sur la page d'accueil.

alter table public.profiles add column if not exists preferred_categories text[] not null default '{}';
alter table public.profiles add column if not exists reading_pace integer;
alter table public.profiles add column if not exists onboarding_completed boolean not null default false;
