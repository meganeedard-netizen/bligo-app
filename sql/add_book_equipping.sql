-- Ajoute une étape de validation "équipé" (plastifié + étiqueté) avant qu'un
-- livre donné par un habitant apparaisse dans le catalogue en ligne.
--
-- Les livres déjà catalogués sont considérés équipés (défaut true, aucun
-- impact rétroactif). Les nouveaux livres ajoutés pendant une session de don
-- sont insérés avec equipped = false et available = false côté admin.html ;
-- un agent doit les marquer "équipé" une fois plastifiés/étiquetés pour
-- qu'ils deviennent visibles dans accueil.html (filtré sur equipped = true)
-- et empruntables (available = true).
alter table public.books add column if not exists equipped boolean not null default true;
