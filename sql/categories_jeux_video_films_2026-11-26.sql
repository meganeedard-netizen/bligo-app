-- Catégories « Jeux vidéo » et « Films » (26/11/2026, demande de Mégane) :
-- les jeux vidéo ne sont plus mélangés aux jeux de société, les DVD ne sont
-- plus rangés dans Culture.
alter table public.books drop constraint books_category_check;
alter table public.books add constraint books_category_check check (category is null or category = any (array[
  'Fonds local', 'Roman', 'Thriller', 'Fantasy', 'Jeunesse', 'BD', 'Poésie & théâtre', 'Documentaire',
  'Sciences & nature', 'Voyages', 'Sports & loisirs', 'Bien-être', 'Maison', 'Histoire', 'Culture',
  'Jeux', 'Jeux vidéo', 'Films', 'Instruments', 'Autres']::text[]));

update public.books set category = 'Jeux vidéo' where format = 'Jeu vidéo' and category is distinct from 'Jeux vidéo';
update public.books set category = 'Films' where format in ('DVD', 'Blu-ray') and category is distinct from 'Films';
