-- À exécuter dans Supabase (SQL Editor > New query > coller > Run)
-- Emplacement physique du livre en médiathèque (ex. "Rayon DAC - étagère 2"),
-- pour retrouver/ranger facilement un livre du catalogue ou de la Bibliothèque libre.

alter table public.books add column if not exists shelf_location text;
alter table public.free_books add column if not exists shelf_location text;
