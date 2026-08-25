

-- Aligne toutes les catégories sur une liste fixe, et empêche toute valeur hors-liste à l'avenir.

update public.books set category = 'Littérature antillaise' where id in (1, 2, 4, 5);
update public.books set category = 'Roman' where id in (3, 6, 7, 8, 11, 12, 19, 20, 21, 22, 23, 24, 25, 27, 30, 31, 32);
update public.books set category = 'Thriller' where id in (9, 10, 13, 14, 15, 16, 17, 18, 33);
update public.books set category = 'Jeunesse' where id in (26, 28);
update public.books set category = 'Autre' where id in (29);

alter table public.books drop constraint if exists books_category_check;
alter table public.books add constraint books_category_check check (
  category is null or category in (
    'Roman', 'Thriller', 'Science-fiction', 'Littérature antillaise', 'BD', 'Mangas',
    'Jeunesse', 'Développement personnel', 'Autobiographie', 'Santé', 'Histoire', 'Sport', 'Magazine', 'Autre'
  )
);
