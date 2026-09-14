-- BliGO — Top Jeunesse (14/09/2026)
-- Une sélection jeunesse permanente (pas datée par mois, contrairement à la
-- Sélection BliGO), avec une tranche d'âge en plus. Même principe : saisie
-- par l'administratrice BliGO, lecture seule côté agents, invisible côté
-- appli usagers.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

create table if not exists public.top_jeunesse_books (
  id bigint generated always as identity primary key,
  rank integer not null unique check (rank between 1 and 20),
  title text not null,
  author text not null,
  age_range text,
  genre text,
  isbn text,
  cover_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.top_jeunesse_books enable row level security;

create policy "Les agents lisent le Top Jeunesse"
  on public.top_jeunesse_books for select
  using (public.is_agent() or public.is_super_admin());

create policy "Seule l'administratrice BliGO gère le Top Jeunesse"
  on public.top_jeunesse_books for all
  using (public.is_super_admin())
  with check (public.is_super_admin());

create or replace function public.touch_top_jeunesse_books()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists touch_top_jeunesse_books_trigger on public.top_jeunesse_books;

create trigger touch_top_jeunesse_books_trigger
  before update on public.top_jeunesse_books
  for each row execute function public.touch_top_jeunesse_books();
