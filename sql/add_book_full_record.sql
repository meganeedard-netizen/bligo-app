-- BliGO — Fiche livre complète côté agent (14/09/2026)
-- Complète les infos manquantes signalées en rendez-vous. Éditeur, date de
-- publication, nombre de pages et langue peuvent être récupérés
-- automatiquement (Google Books / Open Library) au catalogage. Le reste
-- (dépôt légal, traducteur, imprimeur, illustrateur, format, couleur/N&B)
-- n'existe dans aucune base publique : champs texte libres, remplis à la
-- main par l'agent au cas par cas.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

alter table public.books add column if not exists publisher text;          -- éditeur
alter table public.books add column if not exists published_date text;     -- date de publication (parfois juste une année)
alter table public.books add column if not exists page_count integer;      -- nombre de pages
alter table public.books add column if not exists language text;          -- langue d'origine

alter table public.books add column if not exists legal_deposit text;      -- dépôt légal
alter table public.books add column if not exists translator text;         -- traducteur
alter table public.books add column if not exists format text;             -- format (poche, broché, grand format...)
alter table public.books add column if not exists illustrator text;        -- illustrateur (nom et date)
alter table public.books add column if not exists cover_color text;        -- "Couleur" ou "Noir et blanc"
alter table public.books add column if not exists printer text;            -- imprimeur
