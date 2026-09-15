-- BliGO — Corrige la contrainte de catégorie désynchronisée (14/09/2026, en pleine démo)
--
-- La contrainte books_category_check a été redéfinie 3 fois dans l'historique
-- (set_fixed_categories.sql, update_categories_v2.sql, rename_categories_fantasy_bd.sql),
-- mais certaines lignes en base sont restées sur d'anciennes catégories jamais
-- migrées. On les reclasse d'abord (mêmes règles que les anciennes migrations,
-- rejouées ici) avant de remettre la contrainte, sinon l'ajout de la
-- contrainte échoue à cause de ces vieilles lignes.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

-- ========== books ==========
alter table public.books drop constraint if exists books_category_check;

update public.books set category = 'Roman'          where category in ('Roman', 'Littérature antillaise');
update public.books set category = 'Fantasy'        where category in ('Science-Fiction', 'Science-fiction');
update public.books set category = 'BD'             where category in ('BD', 'Mangas', 'BD & Mangas');
update public.books set category = 'Bien-être'      where category in ('Développement personnel', 'Santé', 'Sport');
update public.books set category = 'Autres'         where category in ('Autobiographie', 'Magazine', 'Autre');
-- Filet de sécurité : toute catégorie encore inconnue après ces reclassements
-- part dans "Autres" plutôt que de bloquer la contrainte.
update public.books
  set category = 'Autres'
  where category is not null
    and category not in ('Roman', 'Thriller', 'Fantasy', 'Jeunesse', 'BD', 'Bien-être', 'Maison', 'Histoire', 'Culture', 'Autres');

alter table public.books add constraint books_category_check check (
  category is null or category in (
    'Roman', 'Thriller', 'Fantasy', 'Jeunesse', 'BD',
    'Bien-être', 'Maison', 'Histoire', 'Culture', 'Autres'
  )
);

-- ========== free_books ==========
alter table public.free_books drop constraint if exists free_books_category_check;

update public.free_books set category = 'Roman'          where category in ('Roman', 'Littérature antillaise');
update public.free_books set category = 'Fantasy'        where category in ('Science-Fiction', 'Science-fiction');
update public.free_books set category = 'BD'             where category in ('BD', 'Mangas', 'BD & Mangas');
update public.free_books set category = 'Bien-être'      where category in ('Développement personnel', 'Santé', 'Sport');
update public.free_books set category = 'Autres'         where category in ('Autobiographie', 'Magazine', 'Autre');
update public.free_books
  set category = 'Autres'
  where category is not null
    and category not in ('Roman', 'Thriller', 'Fantasy', 'Jeunesse', 'BD', 'Bien-être', 'Maison', 'Histoire', 'Culture', 'Autres');

alter table public.free_books add constraint free_books_category_check check (
  category is null or category in (
    'Roman', 'Thriller', 'Fantasy', 'Jeunesse', 'BD',
    'Bien-être', 'Maison', 'Histoire', 'Culture', 'Autres'
  )
);
