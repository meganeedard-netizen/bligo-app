-- BliGO — Modèle de données du logiciel back-office agents (13/09/2026)
-- Exemplaires physiques, communautés de communes, prêts, transferts inter-bibliothèques.
--
-- Migration ADDITIVE : ne modifie ni ne supprime aucune table existante.
-- L'appli usager (accueil, réservations, liste d'envie, points, profil) continue
-- de fonctionner sans aucun changement : books.available reste à jour tout seul.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run


-- ============================================================
-- 1. Communautés de communes
-- ============================================================
-- Une communauté de communes regroupe plusieurs médiathèques (parfois des dizaines).
-- La table `communes` existante fait déjà office de médiathèque : elle porte les
-- horaires d'ouverture et le fuseau horaire. On la rattache simplement à sa communauté.

create table if not exists public.communities (
  id bigint generated always as identity primary key,
  name text not null unique,

  -- Réglages contractuels, décidés communauté par communauté
  -- 'community' : la carte vaut sur tout le territoire, on emprunte dans n'importe
  --               quelle médiathèque de la communauté
  -- 'commune'   : on emprunte uniquement dans la médiathèque de sa commune
  lending_scope text not null default 'community'
    check (lending_scope in ('community', 'commune')),

  -- Un livre emprunté ici peut-il être rendu dans une autre médiathèque ?
  returns_anywhere boolean not null default true,

  -- Les transferts de livres entre médiathèques sont-ils activés ?
  transfers_enabled boolean not null default true,

  -- Durée de prêt par défaut, en jours
  loan_duration_days integer not null default 21,

  created_at timestamptz not null default now()
);

alter table public.communities enable row level security;

create policy "Les communautés sont publiques en lecture"
  on public.communities for select
  using (true);

create policy "Seule l'administratrice BliGO gère les communautés"
  on public.communities for all
  using (public.is_super_admin())
  with check (public.is_super_admin());

alter table public.communes
  add column if not exists community_id bigint references public.communities(id);

-- Les communes déjà en base sont rattachées à une communauté par défaut,
-- pour qu'aucune ne se retrouve orpheline.
insert into public.communities (name)
  select 'Communauté pilote'
  where not exists (select 1 from public.communities);

update public.communes
  set community_id = (select id from public.communities order by id limit 1)
  where community_id is null;


-- ============================================================
-- 2. ISBN sur les notices
-- ============================================================
-- Clé naturelle pour retrouver un livre au scan de son code-barres commercial
-- (celui imprimé par l'éditeur au dos du livre) et pour les imports catalogue.

alter table public.books add column if not exists isbn text;

create index if not exists books_isbn_idx on public.books (isbn) where isbn is not null;


-- ============================================================
-- 3. Exemplaires physiques
-- ============================================================
-- C'est la pièce qui manquait : jusqu'ici `books` décrivait un titre, avec un simple
-- booléen `available`. Impossible de distinguer trois exemplaires du même roman, donc
-- impossible de savoir lequel un agent vient de rendre.
--
-- `barcode` est le code-barres propre à la médiathèque, celui collé sur le livre et
-- qui porte la cote de rangement. C'est lui que l'agent scanne pour l'emprunt, le
-- retour et le rangement en rayon.

create table if not exists public.book_copies (
  id bigint generated always as identity primary key,
  book_id bigint not null references public.books(id) on delete cascade,

  -- Code-barres médiathèque, unique sur toute la base centrale
  barcode text not null unique,

  -- Médiathèque propriétaire de l'exemplaire (ne change jamais)
  owner_commune_id bigint not null references public.communes(id),

  -- Médiathèque où l'exemplaire se trouve physiquement en ce moment
  -- (différente de la propriétaire pendant et après un transfert)
  current_commune_id bigint not null references public.communes(id),

  -- Cote de rangement, propre à chaque médiathèque
  shelf_location text,

  status text not null default 'available' check (status in (
    'available',   -- en rayon, empruntable
    'reserved',    -- mis de côté pour une réservation Click & Collect
    'borrowed',    -- emprunté par un usager
    'in_transit',  -- en route vers une autre médiathèque
    'processing',  -- don reçu, en cours d'équipement et d'étiquetage
    'lost',        -- perdu ou non rendu
    'withdrawn'    -- retiré du fonds (trop abîmé, désherbage)
  )),

  condition text,
  acquired_at date not null default current_date,

  -- Provenance : achat de la médiathèque ou don d'un habitant
  source text not null default 'purchase' check (source in ('purchase', 'donation')),
  donation_id bigint,

  created_at timestamptz not null default now()
);

create index if not exists book_copies_book_idx on public.book_copies (book_id);
create index if not exists book_copies_current_idx on public.book_copies (current_commune_id, status);
create index if not exists book_copies_barcode_idx on public.book_copies (barcode);

alter table public.book_copies enable row level security;

create policy "Les exemplaires sont publics en lecture"
  on public.book_copies for select
  using (true);

create policy "Les agents gèrent les exemplaires"
  on public.book_copies for all
  using (public.is_agent() or public.is_super_admin())
  with check (public.is_agent() or public.is_super_admin());


-- ============================================================
-- 4. Reprise de l'existant
-- ============================================================
-- Chaque livre déjà au catalogue reçoit un exemplaire, rattaché à sa commune actuelle,
-- avec un code-barres provisoire reconnaissable (BLIGO-000123). Les agents remplaceront
-- ces codes provisoires par les vrais au fur et à mesure qu'ils rééquiperont les livres.

insert into public.book_copies (book_id, barcode, owner_commune_id, current_commune_id, shelf_location, status)
select
  b.id,
  'BLIGO-' || lpad(b.id::text, 6, '0'),
  coalesce(b.commune_id, (select id from public.communes order by id limit 1)),
  coalesce(b.commune_id, (select id from public.communes order by id limit 1)),
  b.shelf_location,
  case when b.available then 'available' else 'borrowed' end
from public.books b
where not exists (
  select 1 from public.book_copies c where c.book_id = b.id
);


-- ============================================================
-- 5. books.available reste à jour tout seul
-- ============================================================
-- L'appli usager lit `books.available` partout. Plutôt que de la modifier, on garde
-- cette colonne synchronisée automatiquement : un titre est disponible dès qu'au moins
-- un de ses exemplaires est en rayon. Rien à changer côté appli.

create or replace function public.sync_book_availability()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_book bigint := coalesce(new.book_id, old.book_id);
begin
  update public.books
    set available = exists (
      select 1 from public.book_copies
      where book_id = target_book and status = 'available'
    )
  where id = target_book;

  return coalesce(new, old);
end;
$$;

drop trigger if exists sync_book_availability_trigger on public.book_copies;

create trigger sync_book_availability_trigger
  after insert or update of status or delete on public.book_copies
  for each row execute function public.sync_book_availability();


-- ============================================================
-- 6. Prêts
-- ============================================================
-- Aujourd'hui un emprunt n'existe que sous la forme d'une réservation passée à
-- 'recupere'. Une médiathèque prête aussi à un habitant qui se présente au comptoir
-- sans avoir rien réservé : cette table couvre les deux cas.
--
-- `reservation_id` fait le lien quand le prêt vient d'une réservation Click & Collect.

create table if not exists public.loans (
  id bigint generated always as identity primary key,
  copy_id bigint not null references public.book_copies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reservation_id bigint references public.reservations(id) on delete set null,

  -- Médiathèque qui a prêté, et médiathèque où le livre a été rendu
  borrowed_at_commune_id bigint not null references public.communes(id),
  returned_at_commune_id bigint references public.communes(id),

  borrowed_at timestamptz not null default now(),
  due_at timestamptz not null,
  returned_at timestamptz,

  borrowed_by_agent uuid references auth.users(id),
  returned_by_agent uuid references auth.users(id),

  created_at timestamptz not null default now()
);

create index if not exists loans_user_idx on public.loans (user_id, returned_at);
create index if not exists loans_copy_idx on public.loans (copy_id, returned_at);

-- Un exemplaire ne peut pas être prêté deux fois en même temps.
create unique index if not exists loans_one_active_per_copy
  on public.loans (copy_id) where returned_at is null;

alter table public.loans enable row level security;

create policy "Un usager voit ses propres prêts"
  on public.loans for select
  using (auth.uid() = user_id or public.is_agent() or public.is_super_admin());

create policy "Les agents gèrent les prêts"
  on public.loans for all
  using (public.is_agent() or public.is_super_admin())
  with check (public.is_agent() or public.is_super_admin());


-- ============================================================
-- 7. Transferts entre médiathèques
-- ============================================================
-- Un livre réservé aux Trois-Îlets mais disponible au Marin doit voyager. On trace
-- le trajet, on notifie les deux médiathèques, et le statut de l'exemplaire passe
-- à 'in_transit' pendant le voyage.

create table if not exists public.transfers (
  id bigint generated always as identity primary key,
  copy_id bigint not null references public.book_copies(id) on delete cascade,
  from_commune_id bigint not null references public.communes(id),
  to_commune_id bigint not null references public.communes(id),

  -- Renseigné quand le transfert est déclenché par une réservation d'usager
  reservation_id bigint references public.reservations(id) on delete set null,

  status text not null default 'requested' check (status in (
    'requested',   -- demandé, le livre est encore dans sa médiathèque d'origine
    'in_transit',  -- parti, en route
    'received',    -- arrivé et scanné à destination
    'cancelled'
  )),

  requested_by uuid references auth.users(id),
  sent_by uuid references auth.users(id),
  received_by uuid references auth.users(id),

  requested_at timestamptz not null default now(),
  sent_at timestamptz,
  received_at timestamptz,

  notes text,
  created_at timestamptz not null default now()
);

create index if not exists transfers_to_idx on public.transfers (to_commune_id, status);
create index if not exists transfers_from_idx on public.transfers (from_commune_id, status);

alter table public.transfers enable row level security;

create policy "Les agents voient et gèrent les transferts"
  on public.transfers for all
  using (public.is_agent() or public.is_super_admin())
  with check (public.is_agent() or public.is_super_admin());

create policy "Un usager voit le transfert qui le concerne"
  on public.transfers for select
  using (
    reservation_id is not null
    and exists (
      select 1 from public.reservations r
      where r.id = transfers.reservation_id and r.user_id = auth.uid()
    )
  );


-- ============================================================
-- 8. Médiathèque de rattachement de l'agent
-- ============================================================
-- Un agent travaille dans une médiathèque précise. Les écrans du back-office
-- filtrent dessus : il ne voit que les livres et les transferts de chez lui.

create or replace function public.agent_commune_id()
returns bigint
language sql
security definer
set search_path = public
stable
as $$
  select commune_id from public.profiles where id = auth.uid();
$$;
