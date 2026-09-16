-- BliGO — Nettoyage des doublons "J'ai dû rêver trop fort" (Michel Bussi), 16/09/2026
--
-- Deux fiches de test créées le 16/09/2026 en essayant le nouveau bouton de
-- validation du scan (livres ids 58 et 60), en plus de la fiche d'origine du
-- catalogue de démo (id 44, la plus complète : résumé, éditeur, date, pages).
-- Aucun des deux exemplaires de test n'a jamais été emprunté (statut
-- 'available'), suppression sans risque — les exemplaires liés (book_copies)
-- partent automatiquement avec (on delete cascade).
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

delete from public.books where id in (58, 60);
