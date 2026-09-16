-- BliGO — Fusionne les 2 fiches "J'ai dû rêver trop fort" (Michel Bussi) en une
-- seule avec 2 exemplaires, 16/09/2026.
--
-- id 44 : fiche d'origine du catalogue de démo, la plus complète (résumé,
--         éditeur, date, pages) — celle qu'on garde.
-- id 62 : fiche créée en rescannant le livre aujourd'hui, avec son propre
--         exemplaire (BLIGO-000062). On rattache cet exemplaire à la fiche 44
--         au lieu de le perdre, puis on supprime la fiche 62 devenue inutile.
--
-- Résultat : la fiche 44 se retrouve avec 2 exemplaires (BLIGO-000044 et
-- BLIGO-000062), donc "2/2 disponibles" dans le catalogue.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

update public.book_copies set book_id = 44 where book_id = 62;
delete from public.books where id = 62;
