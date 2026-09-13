-- Renomme les catégories "Science-Fiction" → "Fantasy" et "BD & Mangas" → "BD".
-- À exécuter dans l'éditeur SQL de Supabase, après update_categories_v2.sql.

alter table public.books drop constraint if exists books_category_check;

update public.books set category = 'Fantasy' where category = 'Science-Fiction';
update public.books set category = 'BD' where category = 'BD & Mangas';

update public.free_books set category = 'Fantasy' where category = 'Science-Fiction';
update public.free_books set category = 'BD' where category = 'BD & Mangas';

-- Les préférences de lecture déjà choisies par les usagers (onboarding) référencent
-- les anciens libellés dans ce tableau texte : on les met à jour à l'identique.
update public.profiles
set preferred_categories = array_replace(array_replace(preferred_categories, 'Science-Fiction', 'Fantasy'), 'BD & Mangas', 'BD');

alter table public.books add constraint books_category_check check (
  category is null or category in (
    'Roman', 'Thriller', 'Fantasy', 'Jeunesse', 'BD',
    'Bien-être', 'Maison', 'Histoire', 'Culture', 'Autres'
  )
);
