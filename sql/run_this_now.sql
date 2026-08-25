-- À exécuter dans Supabase (SQL Editor > New query > coller > Run)
-- Ajoute la catégorie et le résumé de chaque livre, pour l'aperçu au clic dans le catalogue.

alter table public.books add column if not exists category text;
alter table public.books add column if not exists summary text;

update public.books set category = 'Roman', summary = 'Fresque d''un quartier populaire de Martinique à travers plusieurs générations d''une famille créole, de la période coloniale à l''urbanisation moderne. Prix Goncourt 1992.' where id = 1;
update public.books set category = 'Roman', summary = 'La vie de Télumée, une femme guadeloupéenne confrontée à l''amour, aux épreuves et à la résilience à travers les générations. Un texte fondateur de la littérature caribéenne.' where id = 2;
update public.books set category = 'Roman épistolaire', summary = 'Une veuve sénégalaise écrit une longue lettre à sa meilleure amie, méditant sur le mariage, la polygamie et la condition des femmes dans l''Afrique post-coloniale.' where id = 3;
update public.books set category = 'Poésie', summary = 'Long poème fondateur du mouvement de la Négritude, méditation lyrique sur l''identité, la colonisation et l''héritage martiniquais et africain.' where id = 4;
update public.books set category = 'Roman', summary = 'Un conte initiatique et fantastique suivant Ti Jean dans une quête mêlant folklore caribéen, magie et recherche d''identité.' where id = 5;
update public.books set category = 'Roman', summary = 'Portrait satirique d''un prince africain déchu, confronté aux désillusions des jeunes nations africaines nouvellement indépendantes.' where id = 6;
update public.books set category = 'Roman', summary = 'Meursault, employé indifférent à Alger, commet un acte de violence absurde et affronte l''exigence de sens de la société. Un classique de la littérature existentialiste.' where id = 7;
update public.books set category = 'Roman historique', summary = 'Un village africain confronté à la disparition de ses jeunes hommes à l''aube de la traite négrière transatlantique. Prix Goncourt des lycéens 2013.' where id = 8;
update public.books set category = 'Thriller', summary = 'Un dîner qui tourne au cauchemar : secrets, manipulation et tension psychologique dans ce thriller à l''intrigue redoutable.' where id = 9;
update public.books set category = 'Thriller', summary = 'Un thriller psychologique haletant autour d''une professeure dont le passé cache de sombres secrets, jusqu''au twist final.' where id = 10;
update public.books set category = 'Roman feel-good', summary = 'Un roman chaleureux et plein de vie sur des destins ordinaires qui se croisent à des moments fragiles, entre résilience et lien humain.' where id = 11;
update public.books set category = 'Roman', summary = 'Une saga familiale tendre et bouleversante explorant les secrets et les liens entre plusieurs générations de femmes.' where id = 12;
update public.books set category = 'Thriller', summary = 'Les séances d''une psychothérapeute basculent dans une toile de manipulation et de danger, dans ce thriller psychologique addictif.' where id = 13;
update public.books set category = 'Thriller', summary = 'Un thriller sur l''identité et les vies qu''on aurait pu vivre, avec les retournements de situation caractéristiques de Guillaume Musso.' where id = 14;
update public.books set category = 'Thriller', summary = 'Une femme sans domicile devient gouvernante dans une famille aisée, et se retrouve prise dans un engrenage de mensonges et de danger.' where id = 15;
update public.books set category = 'Thriller', summary = 'Un thriller à suspense où le passé trouble d''une femme refait surface, l''obligeant à affronter des secrets qu''elle croyait enterrés.' where id = 16;
update public.books set category = 'Thriller', summary = 'La suite de « La femme de ménage » : la nouvelle vie de Millie se fissure quand d''anciens secrets et de nouvelles menaces se percutent.' where id = 17;
update public.books set category = 'Thriller', summary = 'La saga continue : Millie affronte un nouveau danger tandis que des vérités enfouies menacent la paix fragile qu''elle a construite.' where id = 18;

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
