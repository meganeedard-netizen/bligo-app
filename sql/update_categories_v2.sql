-- Passage de 14 à 10 catégories (nouvelle organisation des genres, août 2026).
-- À exécuter dans l'éditeur SQL de Supabase.

-- 1) On enlève d'abord l'ancienne contrainte pour pouvoir réécrire les valeurs.
alter table public.books drop constraint if exists books_category_check;

-- 2) Reclassement des livres existants vers les 10 nouvelles catégories.
update public.books set category = 'Roman'         where category in ('Roman', 'Littérature antillaise');
update public.books set category = 'Science-Fiction' where category = 'Science-fiction';
update public.books set category = 'BD & Mangas'    where category in ('BD', 'Mangas');
update public.books set category = 'Bien-être'      where category in ('Développement personnel', 'Santé', 'Sport');
update public.books set category = 'Autres'         where category in ('Autobiographie', 'Magazine', 'Autre');
-- Thriller, Jeunesse, Histoire : le nom ne change pas, rien à faire.

-- 3) Nouvelle contrainte limitée aux 10 catégories.
alter table public.books add constraint books_category_check check (
  category is null or category in (
    'Roman', 'Thriller', 'Science-Fiction', 'Jeunesse', 'BD & Mangas',
    'Bien-être', 'Maison', 'Histoire', 'Culture', 'Autres'
  )
);

-- 4) Même reclassement pour les livres de la bibliothèque libre (fonds hors condition).
update public.free_books set category = 'Roman'          where category in ('Roman', 'Littérature antillaise');
update public.free_books set category = 'Science-Fiction' where category = 'Science-fiction';
update public.free_books set category = 'BD & Mangas'     where category in ('BD', 'Mangas');
update public.free_books set category = 'Bien-être'       where category in ('Développement personnel', 'Santé', 'Sport');
update public.free_books set category = 'Autres'          where category in ('Autobiographie', 'Magazine', 'Autre');
