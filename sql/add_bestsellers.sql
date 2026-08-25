-- À exécuter uniquement si tu as déjà lancé sql/schema.sql une première fois
-- (sinon ignore ce fichier : ces 10 livres sont déjà inclus dans schema.sql).
-- Ajoute le top des ventes national (classement Livres Hebdo) au catalogue.

insert into public.books (title, author, cover_initial, available) values
  ('Le dîner. Une aventure dont vous êtes le héros', 'Freida McFadden', 'D', true),
  ('La prof', 'Freida McFadden', 'P', false),
  ('Les heures fragiles', 'Virginie Grimaldi', 'H', true),
  ('Tata', 'Valérie Perrin', 'T', true),
  ('La psy', 'Freida McFadden', 'P', false),
  ('Quelqu''un d''autre', 'Guillaume Musso', 'Q', true),
  ('La femme de ménage', 'Freida McFadden', 'F', false),
  ('Celle qui sait', 'Riley Sager', 'C', true),
  ('La femme de ménage voit tout', 'Freida McFadden', 'F', true),
  ('Les secrets de la femme de ménage', 'Freida McFadden', 'S', false);
