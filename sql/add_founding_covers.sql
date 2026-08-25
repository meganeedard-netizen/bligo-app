-- À exécuter dans Supabase (SQL Editor > New query > coller > Run)
-- Ajoute de vraies couvertures (trouvées sur Open Library, vérifiées) aux 8 livres
-- fondateurs qui n'en avaient pas encore en base — Google Books avait son quota
-- épuisé aujourd'hui, ce qui les affichait sans couverture dans l'appli.

update public.books set cover_url = 'https://covers.openlibrary.org/b/id/418036-L.jpg' where id = 1;    -- Texaco
update public.books set cover_url = 'https://covers.openlibrary.org/b/id/275192-L.jpg' where id = 2;    -- Pluie et vent sur Télumée Miracle
update public.books set cover_url = 'https://covers.openlibrary.org/b/id/14338907-L.jpg' where id = 3;  -- Une si longue lettre
update public.books set cover_url = 'https://covers.openlibrary.org/b/id/9666094-L.jpg' where id = 4;   -- Cahier d'un retour au pays natal
update public.books set cover_url = 'https://covers.openlibrary.org/b/id/964135-L.jpg' where id = 5;    -- Ti Jean L'horizon
update public.books set cover_url = 'https://covers.openlibrary.org/b/id/13272075-L.jpg' where id = 6;  -- Les Soleils des indépendances
update public.books set cover_url = 'https://covers.openlibrary.org/b/id/13151269-L.jpg' where id = 7;  -- L'Étranger
update public.books set cover_url = 'https://covers.openlibrary.org/b/id/14358557-L.jpg' where id = 8;  -- La Saison de l'ombre
