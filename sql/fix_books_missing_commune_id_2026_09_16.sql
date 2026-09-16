-- BliGO — Corrige des livres sans commune_id, invisibles côté usager (16/09/2026)
--
-- admin.html ne renseignait jamais commune_id à l'insertion d'un nouveau livre
-- (scan simple, scan en rafale, ajout manuel) — corrigé dans le code aujourd'hui,
-- mais les livres déjà scannés avec ce bug restent sans commune_id, donc
-- invisibles dans accueil.html qui filtre justement par commune_id.
--
-- Rattrapage : tous les livres orphelins récupèrent la seule médiathèque en
-- place aujourd'hui (Val-Fleuri, id 1). À adapter si plusieurs médiathèques
-- utilisent BliGO au moment où ce fichier est exécuté.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

update public.books set commune_id = 1 where commune_id is null;
