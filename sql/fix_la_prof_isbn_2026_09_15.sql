-- BliGO — Complète « La Prof » dans la Sélection BliGO (15/09/2026)
-- Le premier résultat Google Books pour ce titre n'avait pas d'ISBN (fiche
-- de mauvaise qualité) — le bon résultat, avec ISBN, était le second, pas
-- vérifié la première fois. Pas d'éditeur ni de dépôt légal trouvés nulle
-- part pour ce livre très récent (sorti fin avril 2026, pas encore
-- complètement catalogué).
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

update public.monthly_top_books
set isbn = '9782290422649',
    published_date = '2026-04-29',
    language = 'fr',
    page_count = 477
where month = '2026-09-01' and rank = 1;

-- Même livre, même trou, dans le Catalogue (id 10) — corrigé au passage.
update public.books
set isbn = '9782290422649',
    published_date = '2026-04-29',
    language = 'fr',
    page_count = 477
where id = 10;
