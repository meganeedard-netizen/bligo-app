-- BliGO — Enrichissement automatique du catalogue de démo (14/09/2026)
-- 34 livres sur 37 complétés via Google Books, Open Library et BnF
-- (ISBN, éditeur, date, pages, langue, format, dépôt légal, imprimeur).
-- N'écrase rien : seuls les champs vides ont été proposés, jamais un titre,
-- une catégorie, un résumé ou une couverture déjà en place.
--
-- Livres non trouvés (à compléter à la main si besoin) : Ti Jean L'horizon,
-- Les Monsieur Madame visitent Fort Boyard, Résister.
--
-- Prérequis : sql/add_book_full_record.sql
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

-- Texaco
update public.books set published_date = '1998', page_count = '182', language = 'fr' where id = 1;

-- Pluie et vent sur Télumée Miracle
update public.books set publisher = 'Seuil', published_date = '1972', page_count = '262', language = 'fr' where id = 2;

-- Une si longue lettre
update public.books set publisher = 'Saint-Paul Editions Religieuses', published_date = '1986', page_count = '104', language = 'fr' where id = 3;

-- Cahier d'un retour au pays natal
update public.books set published_date = '196?', page_count = '108', language = 'fr' where id = 4;

-- Les Soleils des indépendances
update public.books set published_date = '1968', page_count = '184', language = 'fr' where id = 6;

-- L'Étranger
update public.books set isbn = '9798758770481', published_date = '2021-11-03', page_count = '206', language = 'fr' where id = 7;

-- La Saison de l'ombre
update public.books set isbn = '9782266248778', publisher = 'Pocket', published_date = '2015', language = 'fr', legal_deposit = 'DL 2015 · FR 01518666', printer = 'Maury impr.', page_count = '246' where id = 8;

-- Le dîner. Une aventure dont vous êtes le héros
update public.books set isbn = '9782824624471', publisher = 'City Edition', published_date = '2026-07-01', page_count = '185', language = 'fr' where id = 9;

-- La prof
update public.books set publisher = '-', page_count = '318', language = 'fr' where id = 10;

-- Les heures fragiles
update public.books set isbn = '9782080468888', published_date = '2025-05-07', language = 'fr', legal_deposit = 'FR 02539485', page_count = '331' where id = 11;

-- Tata
update public.books set isbn = '9798242818682', publisher = 'Independently Published', published_date = '2026-01-07', language = 'fr' where id = 12;

-- La psy
update public.books set publisher = '-', page_count = '318', language = 'fr' where id = 13;

-- Quelqu'un d'autre
update public.books set isbn = '9782702183939', publisher = 'Calmann-Lévy', published_date = '2024-03-05', page_count = '272', language = 'fr' where id = 14;

-- La femme de ménage
update public.books set isbn = '9782290391174', published_date = '2023', language = 'fr' where id = 15;

-- Celle qui sait
update public.books set isbn = '9782386433474', publisher = 'Verso', published_date = '2026-07-03T00:00:00+02:00', page_count = '419', language = 'fr' where id = 16;

-- La femme de ménage voit tout
update public.books set isbn = '9782824627571', published_date = '2024-10-02', language = 'fr', legal_deposit = 'FR 02462009', page_count = '392' where id = 17;

-- Les secrets de la femme de ménage
update public.books set isbn = '9782824638416', publisher = 'City Edition', published_date = '2023-10-04', page_count = '364', language = 'fr' where id = 18;

-- D'autres printemps
update public.books set isbn = '9782898263484', publisher = 'Édito', published_date = '2026-06-10T00:00:00+02:00', page_count = '263', language = 'fr' where id = 19;

-- L'homme qui lisait des livres
update public.books set isbn = '9782260056874', publisher = 'Julliard', published_date = '2025-08-21', page_count = '73', language = 'fr' where id = 20;

-- L'invitée surprise
update public.books set isbn = '9782898761546', publisher = 'Guy Saint-Jean Éditeur', published_date = '2026-01-21T00:00:00-05:00', page_count = '394', language = 'fr' where id = 21;

-- La Petite bonne
update public.books set isbn = '9782383111290', publisher = 'Les Avrils', published_date = '2024-08-28', page_count = '304', language = 'fr' where id = 22;

-- La Porteuse de lettres
update public.books set isbn = '9782253256366', published_date = '2026-04-15', language = 'fr', page_count = '563' where id = 23;

-- Le Barman du Ritz
update public.books set isbn = '9791026907619', published_date = '2024-09-02', language = 'fr', legal_deposit = 'FR 02453359', page_count = '645' where id = 24;

-- Les Habitantes
update public.books set isbn = '9782707357212', publisher = 'MINUIT', published_date = '2026-01-02T00:00:00+01:00', page_count = '145', language = 'fr' where id = 25;

-- Les saules
update public.books set isbn = '9782380200638', publisher = 'Éditions de l''épée', published_date = '2025-01-10', page_count = '189', language = 'fr' where id = 27;

-- Mortelle Adèle Tome 23 - Nazebrocadabra !
update public.books set isbn = '9782494678767', publisher = 'Mr Tan Company', published_date = '2026-05-28', page_count = '80', language = 'fr' where id = 28;

-- Tout le monde aime Clara
update public.books set isbn = '9782073100412', published_date = '2025-02-06', language = 'fr', legal_deposit = 'FR 02509336', page_count = '192' where id = 30;

-- Un avenir radieux
update public.books set isbn = '9782702183625', published_date = '2025', language = 'fr', legal_deposit = 'FR 02509469', page_count = '585' where id = 31;

-- Un jour sans femme
update public.books set isbn = '9782378804985', publisher = 'Iconoclaste', published_date = '2026-05-07', page_count = '234', language = 'fr' where id = 32;

-- Une unique lueur
update public.books set isbn = '9782080160713', published_date = '2026-04-08', language = 'fr' where id = 33;

-- J'ai dû rêver trop fort
update public.books set isbn = '9782258163683', publisher = 'Presses de la Cité', published_date = '2019-06-27', page_count = '349', language = 'fr' where id = 44;

-- Les 7 habitudes de ceux qui réalisent tout ce qu'ils entreprennent
update public.books set isbn = '9781642508277', publisher = 'Mango Media Inc.', published_date = '2022-08-09', page_count = '236', language = 'en' where id = 48;

-- J'ai dû rêver trop fort
update public.books set publisher = 'Presses de la Cité', published_date = '2019-06-27', page_count = '349', language = 'fr' where id = 58;

-- Tant que fleuriront les citronniers
update public.books set isbn = '9782095041335', published_date = '2025-10-16', language = 'fr' where id = 59;

