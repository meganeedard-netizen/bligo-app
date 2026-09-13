-- Deux avis d'exemple (5 étoiles) sur "Texaco", pour illustrer le module
-- d'avis lors de rendez-vous avec les mairies. Utilise deux comptes usagers
-- déjà existants (les deux premiers inscrits, hors agents/admin) — s'il n'y
-- en a pas assez, l'un des deux avis (ou les deux) ne sera pas ajouté.

do $$
declare
  v_book_id bigint;
  v_user1 uuid;
  v_user2 uuid;
begin
  select id into v_book_id from public.books where title = 'Texaco' limit 1;

  select id into v_user1 from public.profiles where role = 'usager' order by created_at asc limit 1;
  select id into v_user2 from public.profiles where role = 'usager' and id <> v_user1 order by created_at asc limit 1;

  if v_book_id is not null and v_user1 is not null then
    insert into public.book_reviews (book_id, user_id, rating, comment)
    values (v_book_id, v_user1, 5, 'Un chef-d''œuvre de la littérature antillaise ! L''histoire de Texaco m''a beaucoup touché(e), à lire absolument pour comprendre notre histoire.')
    on conflict (book_id, user_id) do nothing;
  end if;

  if v_book_id is not null and v_user2 is not null then
    insert into public.book_reviews (book_id, user_id, rating, comment)
    values (v_book_id, v_user2, 5, 'Magnifique fresque sur Fort-de-France. Chamoiseau a une plume incroyable, on s''y croirait. Un vrai coup de cœur de la médiathèque !')
    on conflict (book_id, user_id) do nothing;
  end if;
end $$;
