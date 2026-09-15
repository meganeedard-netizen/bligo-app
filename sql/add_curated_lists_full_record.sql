-- BliGO — Fiche complète sur Sélection BliGO et Top Jeunesse (15/09/2026)
-- Mêmes champs que la fiche livre du Catalogue (résumé, format, éditeur,
-- date de publication, nombre de pages, langue d'origine), pour les
-- consulter au clic sur un livre dans ces deux listes aussi.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

alter table public.monthly_top_books add column if not exists summary text;
alter table public.monthly_top_books add column if not exists format text;
alter table public.monthly_top_books add column if not exists publisher text;
alter table public.monthly_top_books add column if not exists published_date text;
alter table public.monthly_top_books add column if not exists page_count integer;
alter table public.monthly_top_books add column if not exists language text;

alter table public.top_jeunesse_books add column if not exists summary text;
alter table public.top_jeunesse_books add column if not exists format text;
alter table public.top_jeunesse_books add column if not exists publisher text;
alter table public.top_jeunesse_books add column if not exists published_date text;
alter table public.top_jeunesse_books add column if not exists page_count integer;
alter table public.top_jeunesse_books add column if not exists language text;
