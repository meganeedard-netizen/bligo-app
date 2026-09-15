-- BliGO — Dépôt légal/imprimeur, recherche BnF par titre+auteur (14/09/2026)
-- La recherche par ISBN exact ne trouvait que 6/37 livres (éditions différentes
-- de celles cataloguées par la BnF). La recherche par titre+auteur en trouve
-- 20 de plus, comme pour Google Books/Open Library.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

-- Texaco
update public.books set legal_deposit = '1994' where id = 1;

-- Pluie et vent sur Télumée Miracle
update public.books set legal_deposit = '1972 · FR 07220403', printer = 'impr. Bussière' where id = 2;

-- Une si longue lettre
update public.books set legal_deposit = '1983 · FR 98496673' where id = 3;

-- Cahier d'un retour au pays natal
update public.books set legal_deposit = '[DL 2008] · FR 70810428' where id = 4;

-- Ti Jean L'horizon
update public.books set legal_deposit = '1979 · FR 08103143', printer = 'impr. Hérissey' where id = 5;

-- Les Soleils des indépendances
update public.books set legal_deposit = '1995 · FR 09619805', printer = 'Impr. Firmin-Didot' where id = 6;

-- L'Étranger
update public.books set legal_deposit = '[1961 (DL)]' where id = 7;

-- La prof
update public.books set legal_deposit = 'FR 02532259' where id = 10;

-- Tata
update public.books set legal_deposit = 'FR 02459732' where id = 12;

-- La psy
update public.books set legal_deposit = 'FR 02428646' where id = 13;

-- Quelqu'un d'autre
update public.books set legal_deposit = 'FR 02428689' where id = 14;

-- Les secrets de la femme de ménage
update public.books set legal_deposit = '2023' where id = 18;

-- L'invitée surprise
update public.books set legal_deposit = 'FR 02557519' where id = 21;

-- La Petite bonne
update public.books set legal_deposit = 'FR 02453769' where id = 22;

-- Les Habitantes
update public.books set legal_deposit = 'FR 02611948' where id = 25;

-- Les saules
update public.books set legal_deposit = 'FR 02539304' where id = 27;

-- Résister
update public.books set legal_deposit = 'FR 02616475' where id = 29;

-- J'ai dû rêver trop fort
update public.books set legal_deposit = 'FR 02006508' where id = 44;

-- Les 7 habitudes de ceux qui réalisent tout ce qu'ils entreprennent
update public.books set legal_deposit = '1991 · FR 09202197', printer = 'Impr. Floch' where id = 48;

-- J'ai dû rêver trop fort
update public.books set legal_deposit = 'FR 02006508' where id = 58;

