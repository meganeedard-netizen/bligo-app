-- Script de test (compte megane.edard@hotmail.fr) : repart de zéro et ne
-- laisse que 3 réservations sur ce compte :
--   1. "Un jour sans femme" (Laetitia Colombani) -> statut "Emprunté"
--   2. "Les Habitantes" (Pauline Peyrade) -> statut "En préparation"
--   3. "La Porteuse de lettres" (Francesca Giannone) -> statut "En préparation"

do $$
declare
  v_user_id uuid;
  v_book_un_jour bigint;
  v_book_habitantes bigint;
  v_book_porteuse bigint;
  v_reservation_id bigint;
begin
  select id into v_user_id from auth.users where email = 'megane.edard@hotmail.fr';

  -- Retire toutes les réservations existantes de ce compte test.
  delete from public.reservations where user_id = v_user_id;

  -- 1. "Un jour sans femme" -> Emprunté (même parcours qu'un vrai usager :
  -- préparation -> prêt -> récupéré, pour déclencher les triggers existants).
  select id into v_book_un_jour from public.books where title = 'Un jour sans femme' and author = 'Laetitia Colombani';
  if v_book_un_jour is null then raise exception 'Livre "Un jour sans femme" introuvable dans le catalogue.'; end if;

  insert into public.reservations (user_id, book_id, status)
  values (v_user_id, v_book_un_jour, 'preparation')
  returning id into v_reservation_id;
  update public.reservations set status = 'pret' where id = v_reservation_id;
  update public.reservations set status = 'recupere' where id = v_reservation_id;

  -- 2. "Les Habitantes" -> En préparation.
  select id into v_book_habitantes from public.books where title = 'Les Habitantes' and author = 'Pauline Peyrade';
  if v_book_habitantes is null then raise exception 'Livre "Les Habitantes" introuvable dans le catalogue.'; end if;
  insert into public.reservations (user_id, book_id, status) values (v_user_id, v_book_habitantes, 'preparation');

  -- 3. "La Porteuse de lettres" -> En préparation.
  select id into v_book_porteuse from public.books where title = 'La Porteuse de lettres' and author = 'Francesca Giannone';
  if v_book_porteuse is null then raise exception 'Livre "La Porteuse de lettres" introuvable dans le catalogue.'; end if;
  insert into public.reservations (user_id, book_id, status) values (v_user_id, v_book_porteuse, 'preparation');
end $$;
