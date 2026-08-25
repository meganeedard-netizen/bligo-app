-- À exécuter dans Supabase (SQL Editor > New query > coller > Run)
-- Ajoute les vraies photos de couverture aux livres déjà en base,
-- et ajoute 15 nouveaux titres avec leur vraie couverture.

alter table public.books add column if not exists cover_url text;

-- Vraies couvertures pour les livres déjà présents
update public.books set cover_url = 'img/covers/le-diner.jpg' where id = 9;
update public.books set cover_url = 'img/covers/la-prof.jpg' where id = 10;
update public.books set cover_url = 'img/covers/les-heures-fragiles.jpg' where id = 11;
update public.books set cover_url = 'img/covers/tata.jpg' where id = 12;
update public.books set cover_url = 'img/covers/la-psy.jpg' where id = 13;
update public.books set cover_url = 'img/covers/quelquun-dautre.jpg' where id = 14;
update public.books set cover_url = 'img/covers/femme-de-menage.jpg' where id = 15;
update public.books set cover_url = 'img/covers/celle-qui-sait.jpg' where id = 16;
update public.books set cover_url = 'img/covers/femme-de-menage-voit-tout.jpg' where id = 17;

-- Nouveaux titres
insert into public.books (title, author, cover_initial, available, category, summary, cover_url) values
  ('D''autres printemps', 'Virginie Grimaldi', 'D', true, 'Roman feel-good', 'Un roman tout en tendresse sur les seconds départs et les liens familiaux qui se réinventent avec le temps.', 'img/covers/dautres-printemps.jpg'),
  ('L''homme qui lisait des livres', 'Rachid Benzine', 'H', true, 'Roman', 'Le portrait d''un homme pour qui la lecture est un refuge et une manière de comprendre le monde, entre transmission et émotion.', 'img/covers/lhomme-qui-lisait-des-livres.jpg'),
  ('L''invitée surprise', 'Alison Espach', 'I', false, 'Roman', 'Une comédie dramatique pleine de charme sur les secrets de famille qui refont surface le temps d''une réunion inattendue.', 'img/covers/linvitee-surprise.jpg'),
  ('La Petite bonne', 'Bérénice Pichat', 'P', true, 'Roman', 'Le récit sensible d''une jeune femme confrontée à la dureté du travail domestique et à la quête de sa propre place.', 'img/covers/la-petite-bonne.jpg'),
  ('La Porteuse de lettres', 'Francesca Giannone', 'P', true, 'Roman historique', 'Dans l''Italie du sud du XXe siècle, une factrice bouscule les traditions d''un village et devient une figure d''émancipation.', 'img/covers/la-porteuse-de-lettres.jpg'),
  ('Le Barman du Ritz', 'Philippe Collin', 'B', false, 'Roman historique', 'Paris, l''Occupation : le destin d''un barman du prestigieux hôtel Ritz, témoin discret d''une époque trouble.', 'img/covers/le-barman-du-ritz.jpg'),
  ('Les Habitantes', 'Pauline Peyrade', 'H', true, 'Roman', 'Un texte intense sur la vie de plusieurs femmes dans un même immeuble, entre solitude et sororité.', 'img/covers/les-habitantes.jpg'),
  ('Les Monsieur Madame visitent Fort Boyard', 'Roger Hargreaves', 'M', true, 'Jeunesse', 'Les personnages cultes de Monsieur Madame partent à l''aventure sur le célèbre fort, pour les plus jeunes lecteurs.', 'img/covers/monsieur-madame-fort-boyard.jpg'),
  ('Les saules', 'Mathilde Beaussault', 'S', false, 'Roman', 'Un roman à l''atmosphère envoûtante, entre nature, mémoire et secrets de famille.', 'img/covers/les-saules.jpg'),
  ('Mortelle Adèle Tome 23 - Nazebrocadabra !', 'Mr Tan & Diane Le Feyer', 'M', true, 'Jeunesse', 'Nouvelle aventure déjantée d''Adèle, l''héroïne préférée des jeunes lecteurs, toujours aussi grinçante et drôle.', 'img/covers/mortelle-adele-23.jpg'),
  ('Résister', 'Salomé Saqué', 'R', true, 'Essai', 'Un essai engagé sur les mobilisations citoyennes et politiques contemporaines, par la journaliste Salomé Saqué.', 'img/covers/resister.jpg'),
  ('Tout le monde aime Clara', 'David Foenkinos', 'T', false, 'Roman', 'Foenkinos signe un roman choral plein de finesse autour du destin de Clara, entre légèreté et profondeur.', 'img/covers/tout-le-monde-aime-clara.jpg'),
  ('Un avenir radieux', 'Pierre Lemaitre', 'U', true, 'Roman', 'Pierre Lemaitre déploie une fresque romanesque ambitieuse, entre satire sociale et sens du récit.', 'img/covers/un-avenir-radieux.jpg'),
  ('Un jour sans femme', 'Laetitia Colombani', 'U', true, 'Roman', 'Laetitia Colombani interroge la condition féminine à travers un récit poignant et engagé.', 'img/covers/un-jour-sans-femme.jpg'),
  ('Une unique lueur', 'Fred Vargas', 'U', false, 'Roman policier', 'Une nouvelle enquête du commissaire Adamsberg, portée par l''univers singulier et atmosphérique de Fred Vargas.', 'img/covers/une-unique-lueur.jpg');
