-- Script de test (compte megane.edard@hotmail.fr) : simule le parcours
-- complet d'une réservation jusqu'à "Récupéré" pour "Mortelle Adèle Tome 23"
-- (id 28), afin de visualiser le nouveau statut "Livre emprunté" (vert
-- foncé) dans Mes réservations sans avoir besoin d'un vrai agent pour
-- scanner/valider. Passe par les mêmes statuts qu'un vrai parcours
-- (préparation → prêt → récupéré) pour déclencher les triggers existants
-- (ready_at, return_due_at à +21 jours, notifications).

do $$
declare
  v_user_id uuid;
  v_reservation_id bigint;
begin
  select id into v_user_id from auth.users where email = 'megane.edard@hotmail.fr';

  insert into public.reservations (user_id, book_id, status)
  values (v_user_id, 28, 'preparation')
  returning id into v_reservation_id;

  update public.reservations set status = 'pret' where id = v_reservation_id;
  update public.reservations set status = 'recupere' where id = v_reservation_id;
end $$;
