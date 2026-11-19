-- Réseau de démo (19/11/2026) : quelques transferts EN COURS pour montrer
-- l'écran Transferts à une BDP (avant : seulement des dépôts déjà reçus).
-- Uniquement des exemplaires DEMO-*, communes 8 à 11 (réseau caché).
insert into public.transfers (copy_id, from_commune_id, to_commune_id, status, kind, requested_at, sent_at, notes) values
  (249, 8, 11, 'requested',  'depot',    now() - interval '1 day',  null,                        'Dépôt demandé par la bibliothèque'),
  (251, 8, 9,  'requested',  'depot',    now() - interval '2 days', null,                        'Dépôt demandé par la bibliothèque'),
  (250, 8, 10, 'in_transit', 'depot',    now() - interval '3 days', now() - interval '1 day',    'Dépôt demandé par la bibliothèque'),
  (276, 9, 10, 'in_transit', 'standard', now() - interval '2 days', now() - interval '5 hours',  'Réservation d''un usager de Valle-Rossa'),
  (277, 9, 11, 'requested',  'standard', now() - interval '6 hours', null,                       'Réservation d''un usager de Pietra-Bianca');
update public.book_copies set status = 'in_transit' where id in (250, 276) and barcode like 'DEMO-%';
