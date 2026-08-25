-- Permet à la médiathèque de mettre un livre en avant sur l'écran d'accueil ("coup de cœur").
alter table public.books add column if not exists is_featured boolean not null default false;

update public.books set is_featured = false;
update public.books set is_featured = true where id = 1; -- Texaco, Patrick Chamoiseau
