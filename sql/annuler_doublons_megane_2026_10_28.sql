-- 28/10/2026 : annule les 2 commandes en double de megane.edard@hotmail.fr
-- (livres déjà commandés par contact@kudjatravel.com). Même chose que
-- « Annuler » dans Mes réservations (suppression de la commande).
delete from public.reservations r
 using auth.users u
 where u.id = r.user_id
   and u.email = 'megane.edard@hotmail.fr'
   and r.id in (76, 82)
   and r.status = 'preparation'
returning r.id, r.book_id, r.status;
