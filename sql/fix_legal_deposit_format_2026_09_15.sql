-- BliGO — Corrige le format du dépôt légal (15/09/2026)
-- Le champ mélangeait l'année de dépôt légal avec le numéro de référence
-- interne de la BnF (FR xxxxxxxx), qui n'est pas une date. Ne garde plus que
-- l'année quand elle existe (la BnF ne donne jamais le mois), vide sinon.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

update public.books set legal_deposit = 'DL 2015' where id = 8;
update public.books set legal_deposit = null where id = 11;
update public.books set legal_deposit = null where id = 17;
update public.books set legal_deposit = null where id = 24;
update public.books set legal_deposit = null where id = 30;
update public.books set legal_deposit = null where id = 31;
update public.books set legal_deposit = '1972' where id = 2;
update public.books set legal_deposit = '1983' where id = 3;
update public.books set legal_deposit = '[DL 2008]' where id = 4;
update public.books set legal_deposit = '1979' where id = 5;
update public.books set legal_deposit = '1995' where id = 6;
update public.books set legal_deposit = null where id = 10;
update public.books set legal_deposit = null where id = 12;
update public.books set legal_deposit = null where id = 13;
update public.books set legal_deposit = null where id = 14;
update public.books set legal_deposit = null where id = 21;
update public.books set legal_deposit = null where id = 22;
update public.books set legal_deposit = null where id = 25;
update public.books set legal_deposit = null where id = 27;
update public.books set legal_deposit = null where id = 29;
update public.books set legal_deposit = null where id = 44;
update public.books set legal_deposit = '1991' where id = 48;
update public.books set legal_deposit = null where id = 58;
