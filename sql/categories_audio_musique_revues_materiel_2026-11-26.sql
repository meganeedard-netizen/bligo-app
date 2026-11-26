-- Catégories Livres audio, Musique, Revues, Matériel (26/11/2026, demande de Mégane).
alter table public.books drop constraint books_category_check;
alter table public.books add constraint books_category_check check (category is null or category = any (array[
  'Fonds local', 'Roman', 'Thriller', 'Fantasy', 'Jeunesse', 'BD', 'Poésie & théâtre', 'Documentaire',
  'Sciences & nature', 'Voyages', 'Sports & loisirs', 'Bien-être', 'Maison', 'Histoire', 'Culture',
  'Jeux', 'Jeux vidéo', 'Films', 'Livres audio', 'Musique', 'Revues', 'Instruments', 'Matériel', 'Autres']::text[]));
insert into public.document_types (commune_id, label, kind, sort_order)
select null, 'Matériel (liseuse, tablette…)', 'autre', coalesce(max(sort_order), 0) + 1 from public.document_types where commune_id is null
  and not exists (select 1 from public.document_types where commune_id is null and label = 'Matériel (liseuse, tablette…)');
update public.books set category = 'Livres audio' where format = 'Livre audio' and category is distinct from 'Livres audio';
update public.books set category = 'Musique' where format = 'CD audio' and category is distinct from 'Musique';
update public.books set category = 'Revues' where format like 'Périodiques%' and category is distinct from 'Revues';
