-- Fondations multi-communes : table des communes, rattachement du catalogue officiel
-- à sa commune, et création de la Bibliothèque Libre (livres "hors condition"),
-- consultable et empruntable dans n'importe quelle commune, sans condition de résidence.

create table public.communes (
  id bigint generated always as identity primary key,
  name text not null unique,
  timezone text not null default 'America/Guadeloupe',
  opening_hours text not null default '',
  created_at timestamptz not null default now()
);

alter table public.communes enable row level security;

create policy "Les communes sont publiques en lecture"
  on public.communes for select
  using (true);

insert into public.communes (name, timezone, opening_hours) values
  ('Val-Fleuri', 'America/Guadeloupe', 'Mardi-Vendredi 10h-18h · Samedi 10h-13h · Fermé dimanche et lundi'),
  ('Le Moule', 'America/Guadeloupe', 'Mardi-Samedi 9h-17h30 · Fermé dimanche et lundi'),
  ('Sainte-Anne', 'America/Guadeloupe', 'Mardi-Vendredi 9h30-17h · Samedi 9h30-12h30 · Fermé dimanche et lundi');

-- Le catalogue officiel reste rattaché à sa commune d'origine (le prêt physique
-- ne peut pas voyager instantanément entre deux bâtiments).
alter table public.books add column if not exists commune_id bigint references public.communes(id);
update public.books set commune_id = (select id from public.communes where name = 'Val-Fleuri') where commune_id is null;

-- Bibliothèque Libre : livres donnés, hors catalogue officiel, sans condition de
-- résidence, consultables et empruntables depuis n'importe quelle commune.
create table public.free_books (
  id bigint generated always as identity primary key,
  commune_id bigint not null references public.communes(id),
  title text not null,
  author text not null,
  cover_initial text not null default '',
  cover_url text,
  category text,
  summary text,
  available boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.free_books enable row level security;

create policy "La Bibliothèque Libre est publique en lecture"
  on public.free_books for select
  using (true);

-- Emprunter un livre de la Bibliothèque Libre : bascule available=false de façon
-- sûre (via une fonction plutôt qu'un accès direct en écriture pour les usagers).
create or replace function public.borrow_free_book(p_book_id bigint)
returns boolean
language plpgsql
security definer
as $$
declare
  affected int;
begin
  update public.free_books set available = false
  where id = p_book_id and available = true;
  get diagnostics affected = row_count;
  return affected > 0;
end;
$$;

grant execute on function public.borrow_free_book(bigint) to authenticated;

insert into public.free_books (commune_id, title, author, cover_initial, category, summary, available) values
  ((select id from public.communes where name = 'Val-Fleuri'), 'Le Petit Prince', 'Antoine de Saint-Exupéry', 'P', 'Jeunesse', 'Un classique intemporel offert par un habitant, à emprunter librement.', true),
  ((select id from public.communes where name = 'Val-Fleuri'), 'Vingt mille lieues sous les mers', 'Jules Verne', 'V', 'Roman', 'Un exemplaire donné par un habitant de Val-Fleuri, disponible en échange libre.', true),
  ((select id from public.communes where name = 'Le Moule'), 'Notre-Dame de Paris', 'Victor Hugo', 'N', 'Roman', 'Don d''un habitant du Moule, à récupérer sur place.', true),
  ((select id from public.communes where name = 'Le Moule'), 'Contes et légendes de Guadeloupe', 'Collectif', 'C', 'Littérature antillaise', 'Recueil offert à la Bibliothèque Libre du Moule.', false),
  ((select id from public.communes where name = 'Sainte-Anne'), 'Le Comte de Monte-Cristo', 'Alexandre Dumas', 'C', 'Roman', 'Un classique donné par un habitant de Sainte-Anne.', true);
