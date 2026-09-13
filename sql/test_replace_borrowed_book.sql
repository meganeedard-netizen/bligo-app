-- Script de test (compte megane.edard@hotmail.fr) : retire l'emprunt de test
-- "Mortelle Adèle Tome 23" et le remplace par "Un jour sans femme" de
-- Laetitia Colombani, dans le même état "Emprunté" (statut "recupere"),
-- pour continuer à visualiser le statut "Livre emprunté" en test.

do $$
declare
  v_user_id uuid;
  v_book_id bigint;
  v_reservation_id bigint;
begin
  select id into v_user_id from auth.users where email = 'megane.edard@hotmail.fr';

  -- Retire l'ancien emprunt de test (Mortelle Adèle Tome 23, id 28).
  delete from public.reservations
  where user_id = v_user_id and book_id = 28 and status = 'recupere';

  -- Recrée le même parcours de test avec "Un jour sans femme".
  select id into v_book_id from public.books where title = 'Un jour sans femme' and author = 'Laetitia Colombani';

  if v_book_id is null then
    raise exception 'Livre "Un jour sans femme" introuvable dans le catalogue.';
  end if;

  insert into public.reservations (user_id, book_id, status)
  values (v_user_id, v_book_id, 'preparation')
  returning id into v_reservation_id;

  update public.reservations set status = 'pret' where id = v_reservation_id;
  update public.reservations set status = 'recupere' where id = v_reservation_id;
end $$;
