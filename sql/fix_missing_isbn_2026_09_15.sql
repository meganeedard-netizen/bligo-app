-- BliGO — Complète l'ISBN pour 5 livres du Catalogue (15/09/2026)
-- Suite au signalement de « La Prof » : le premier résultat Google Books
-- n'avait pas toujours d'ISBN ou était la mauvaise édition. Vérifié un par un :
--
-- Exclus (mauvaise édition trouvée, laissés tels quels) :
-- Texaco (édition anglaise), Pluie et vent sur Télumée Miracle (édition
-- anglaise), Cahier d'un retour au pays natal (fiche de lecture, pas le vrai
-- livre), Les Monsieur Madame visitent Fort Boyard (toujours introuvable).
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

-- Une si longue lettre
update public.books set isbn = '9782385060398' where id = 3;

-- Ti Jean L'horizon
update public.books set isbn = '9782373111019' where id = 5;

-- Les Soleils des indépendances
update public.books set isbn = '9782020125987', publisher = 'Seuil', published_date = '1995', page_count = '212', language = 'fr' where id = 6;

-- La psy
update public.books set isbn = '9782824638874' where id = 13;

-- Résister
update public.books set isbn = '9782228937597', published_date = '2024-10-16', language = 'fr' where id = 29;

