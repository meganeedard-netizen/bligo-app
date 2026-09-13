-- BliGO — Dons de livres (points de fidélité) + banque de couvertures
-- À exécuter dans Supabase (SQL Editor > New query > coller > Run), après add_superadmin_communes.sql

-- 1. Dons : un agent scanne la carte du donateur (s'il a un compte), puis scanne les
-- livres donnés — chacun crédite automatiquement des points de fidélité au donateur.
create table public.donations (
  id bigint generated always as identity primary key,
  donor_id uuid references auth.users(id),
  book_id bigint references public.books(id) on delete set null,
  free_book_id bigint references public.free_books(id) on delete set null,
  title text not null,
  author text not null,
  points_awarded integer not null default 10,
  created_at timestamptz not null default now()
);

alter table public.donations enable row level security;

create policy "Agent ou super-admin voit les dons"
  on public.donations for select
  using (public.is_agent() or public.is_super_admin());

-- Volontairement aucune policy insert/update/delete : tout écrit passe par le RPC
-- record_donation() ci-dessous (même logique que borrow_free_book() dans schema.sql),
-- pour ne jamais laisser un client attribuer des points à n'importe quel compte.

-- 2. RPC appelé depuis admin.html à chaque livre catalogué pendant une session de don.
create or replace function public.record_donation(
  p_donor_id uuid,
  p_book_id bigint default null,
  p_free_book_id bigint default null,
  p_title text default null,
  p_author text default null
)
returns public.donations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_author text;
  v_points integer := 10;
  v_row public.donations;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Non autorisé';
  end if;

  if p_book_id is not null then
    select title, author into v_title, v_author from public.books where id = p_book_id;
  elsif p_free_book_id is not null then
    select title, author into v_title, v_author from public.free_books where id = p_free_book_id;
  else
    v_title := coalesce(p_title, 'Titre inconnu');
    v_author := coalesce(p_author, 'Auteur inconnu');
  end if;

  insert into public.donations (donor_id, book_id, free_book_id, title, author, points_awarded)
  values (p_donor_id, p_book_id, p_free_book_id, v_title, v_author, v_points)
  returning * into v_row;

  if p_donor_id is not null then
    update public.profiles set loyalty_points = loyalty_points + v_points where id = p_donor_id;
  end if;

  return v_row;
end;
$$;

grant execute on function public.record_donation(uuid, bigint, bigint, text, text) to authenticated;

-- 3. Banque de couvertures : quand Mégane ajoute une image (super_admin uniquement) pour
-- un livre sans couverture, elle est réutilisée automatiquement pour tout futur livre au
-- même titre/auteur (recherchée par clé normalisée simple : minuscules + espaces réduits).
-- Pas de table "couvertures manquantes" séparée : la file d'attente dans superadmin.html
-- est simplement `select ... from books/free_books where cover_url is null`, toujours à
-- jour et qui se vide d'elle-même dès qu'une couverture est renseignée.
create table public.cover_bank (
  id bigint generated always as identity primary key,
  title_key text not null,
  author_key text not null,
  image_url text not null,
  created_at timestamptz not null default now(),
  unique (title_key, author_key)
);

alter table public.cover_bank enable row level security;

create policy "La banque de couvertures est publique en lecture"
  on public.cover_bank for select
  using (true);

create policy "Un super-admin alimente la banque de couvertures"
  on public.cover_bank for insert
  with check (public.is_super_admin());

create policy "Un super-admin met à jour la banque de couvertures"
  on public.cover_bank for update
  using (public.is_super_admin());

-- 4. Policies UPDATE pour que superadmin.html puisse renseigner cover_url.
-- free_books n'a aujourd'hui AUCUNE policy update (seul borrow_free_book() contourne la RLS).
create policy "Un super-admin modifie les livres"
  on public.books for update
  using (public.is_super_admin());

create policy "Un super-admin modifie la bibliothèque libre"
  on public.free_books for update
  using (public.is_super_admin());

-- 5. Bucket de stockage pour les images de couverture, public en lecture.
-- Si cet insert est refusé par l'éditeur SQL de ton projet Supabase (rare, selon le plan),
-- crée le bucket à la main : Dashboard > Storage > New bucket > nom "book-covers" > Public ON,
-- puis exécute seulement les 3 "create policy" ci-dessous.
insert into storage.buckets (id, name, public)
values ('book-covers', 'book-covers', true)
on conflict (id) do nothing;

create policy "Lecture publique des couvertures"
  on storage.objects for select
  using (bucket_id = 'book-covers');

create policy "Un super-admin dépose des couvertures"
  on storage.objects for insert
  with check (bucket_id = 'book-covers' and public.is_super_admin());

create policy "Un super-admin remplace des couvertures"
  on storage.objects for update
  using (bucket_id = 'book-covers' and public.is_super_admin())
  with check (bucket_id = 'book-covers' and public.is_super_admin());
