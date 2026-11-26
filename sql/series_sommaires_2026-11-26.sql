-- Séries (BD, mangas, sagas) et sommaires (articles d'une revue, chapitres
-- d'un ouvrage collectif) : 26/11/2026, RDV Brest Métropole.
alter table public.books add column if not exists series_name text;
alter table public.books add column if not exists series_number numeric;
alter table public.books add column if not exists contents text;
create index if not exists books_series_idx on public.books (commune_id, lower(series_name)) where series_name is not null;
