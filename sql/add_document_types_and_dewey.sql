-- Indice Dewey, fiche enrichie et types de documents gérés par la direction (07/10/2026)
-- ============================================================
-- 1. Nouvelles colonnes de la fiche document, remplies au catalogage depuis
--    la BnF (UNIMARC) et Open Library :
--    - dewey       : indice Dewey complet (BnF tag 676, Open Library)
--    - collection  : collection éditeur et numéro (BnF tag 225)
--    - subjects    : sujets Rameau (BnF tags 606/607), utiles à la recherche
--    - binding     : reliure (BnF tag 010 $b, ex. « rel. » → « Relié »)
--    - dimensions  : format physique (BnF tag 215 $d, ex. « 32 cm »)
--    - illustrations : mention d'illustration (BnF tag 215 $c, ex. « ill. en coul. »)
-- 2. Table document_types : la liste « Type de document » du catalogage
--    (anciennement figée dans admin.html), complétable par la direction de
--    chaque médiathèque dans Réglages. commune_id null = liste commune à
--    toutes les médiathèques (seul le super admin la modifie).
--    books.format garde le libellé choisi (texte), rien à migrer.

alter table public.books add column if not exists dewey text;
alter table public.books add column if not exists collection text;
alter table public.books add column if not exists subjects text;
alter table public.books add column if not exists dimensions text;
alter table public.books add column if not exists binding text;
alter table public.books add column if not exists illustrations text;

create table if not exists public.document_types (
  id bigint generated always as identity primary key,
  commune_id bigint references public.communes(id) on delete cascade,
  label text not null,
  -- Sert au catalogage : un code-barres de CD trouvé sur MusicBrainz prend
  -- automatiquement le premier type 'cd' de la liste.
  kind text not null default 'livre' check (kind in ('livre', 'periodique', 'cd', 'dvd', 'autre')),
  sort_order integer not null default 100,
  created_at timestamptz not null default now()
);

create unique index if not exists document_types_unique_label
  on public.document_types (coalesce(commune_id, 0), lower(label));

alter table public.document_types enable row level security;

drop policy if exists "Tout le monde lit les types de documents" on public.document_types;
create policy "Tout le monde lit les types de documents"
  on public.document_types for select
  using (true);

drop policy if exists "La direction gère les types de sa médiathèque" on public.document_types;
create policy "La direction gère les types de sa médiathèque"
  on public.document_types for all
  using (public.is_super_admin() or (public.is_direction() and commune_id = public.agent_commune_id()))
  with check (public.is_super_admin() or (public.is_direction() and commune_id = public.agent_commune_id()));

-- Liste de départ : les 6 types déjà utilisés (mêmes libellés exacts, pour
-- que les fiches existantes restent reconnues), plus les supports non-livres.
insert into public.document_types (commune_id, label, kind, sort_order) values
  (null, 'Livre broché', 'livre', 10),
  (null, 'Livre relié', 'livre', 20),
  (null, 'Livre de poche', 'livre', 30),
  (null, 'Livre audio', 'livre', 40),
  (null, 'Périodiques (journaux quotidiens, magazines, revues spécialisées)', 'periodique', 50),
  (null, 'Beaux livres et usuels (encyclopédies, dictionnaires, atlas, livres d''art)', 'livre', 60),
  (null, 'Documents graphiques et cartographiques (cartes, plans, estampes, partitions)', 'autre', 70),
  (null, 'CD audio', 'cd', 80),
  (null, 'DVD', 'dvd', 90),
  (null, 'Jeu de société', 'autre', 100)
on conflict do nothing;
