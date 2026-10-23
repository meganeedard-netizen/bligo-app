-- Contenu du compte démo Apple (23/10/2026)
-- Pour que le vérificateur d'Apple puisse tester tous les écrans avec
-- demo-apple@bligo.fr (Val-Fleuri) :
--   • 3 livres déjà empruntés et rendus → historique, possibilité de noter et
--     de laisser un avis ;
--   • 1 livre en cours d'emprunt (retour dans 14 jours) → prolongation ;
--   • 2 livres dans la liste d'envie ;
--   • des points de fidélité et les badges correspondants.
-- Supprime aussi l'événement de test « rara » (id 8) à Val-Fleuri.
-- Relançable : ne recrée rien si le compte a déjà son contenu.

do $$
declare
  v_uid uuid;
  v_book bigint;
  v_copy bigint;
  v_resa bigint;
  v_done int := 0;
begin
  select id into v_uid from auth.users where email = 'demo-apple@bligo.fr';
  if v_uid is null then raise exception 'Compte demo-apple@bligo.fr introuvable'; end if;

  if exists (select 1 from public.reservations where user_id = v_uid) then
    raise notice 'Le compte démo a déjà des emprunts : rien à ajouter.';
  else
    -- Historique : 3 livres rendus (Texaco, L'Étranger, Une si longue lettre,
    -- ou d'autres livres de Val-Fleuri ayant un exemplaire en rayon).
    for v_book, v_copy in
      select distinct on (b.id) b.id, c.id
      from public.books b
      join public.book_copies c on c.book_id = b.id and c.owner_commune_id = 1 and c.status = 'available'
      where b.commune_id = 1
      order by b.id, c.id
    loop
      exit when v_done >= 3;
      insert into public.reservations (user_id, book_id, status, created_at, ready_at, return_due_at, review_reminded)
      values (v_uid, v_book, 'recupere', now() - interval '60 days' + v_done * interval '5 days',
              now() - interval '58 days' + v_done * interval '5 days', now() - interval '37 days' + v_done * interval '5 days', true)
      returning id into v_resa;
      insert into public.loans (copy_id, user_id, reservation_id, borrowed_at_commune_id, returned_at_commune_id,
                                borrowed_at, due_at, returned_at)
      values (v_copy, v_uid, v_resa, 1, 1,
              now() - interval '58 days' + v_done * interval '5 days', now() - interval '37 days' + v_done * interval '5 days',
              now() - interval '40 days' + v_done * interval '5 days');
      v_done := v_done + 1;
    end loop;

    -- Emprunt en cours : La Porteuse de lettres (ou un autre livre disponible).
    select b.id, c.id into v_book, v_copy
    from public.books b
    join public.book_copies c on c.book_id = b.id and c.owner_commune_id = 1 and c.status = 'available'
    where b.commune_id = 1
      and b.id not in (select book_id from public.reservations where user_id = v_uid)
    order by (b.title = 'La Porteuse de lettres') desc, b.id desc
    limit 1;
    if v_copy is not null then
      insert into public.reservations (user_id, book_id, status, created_at, ready_at, return_due_at)
      values (v_uid, v_book, 'recupere', now() - interval '9 days', now() - interval '7 days', now() + interval '14 days')
      returning id into v_resa;
      insert into public.loans (copy_id, user_id, reservation_id, borrowed_at_commune_id, borrowed_at, due_at)
      values (v_copy, v_uid, v_resa, 1, now() - interval '7 days', now() + interval '14 days');
      update public.book_copies set status = 'borrowed' where id = v_copy;
    end if;

    -- Liste d'envie : 2 livres pas encore empruntés.
    insert into public.wishlist (user_id, book_id)
    select v_uid, b.id from public.books b
    where b.commune_id = 1 and b.id not in (select book_id from public.reservations where user_id = v_uid)
    order by b.id desc offset 1 limit 2
    on conflict do nothing;

    -- Points de fidélité et badges.
    update public.profiles set loyalty_points = greatest(loyalty_points, 120) where id = v_uid;
    perform public.check_and_award_badges(v_uid);
  end if;

  -- Événement de test « rara » à supprimer (demandé par Mégane le 23/10/2026).
  delete from public.events where id = 8 and title = 'rara';
end;
$$;

-- Vérification : ce que verra le vérificateur d'Apple.
select 'emprunt' as type, b.title, l.due_at, l.returned_at
from public.loans l join public.book_copies c on c.id = l.copy_id join public.books b on b.id = c.book_id
where l.user_id = (select id from auth.users where email = 'demo-apple@bligo.fr')
union all
select 'liste envie', b.title, null, null
from public.wishlist w join public.books b on b.id = w.book_id
where w.user_id = (select id from auth.users where email = 'demo-apple@bligo.fr')
union all
select 'points : ' || loyalty_points, null, null, null from public.profiles
where id = (select id from auth.users where email = 'demo-apple@bligo.fr')
union all
select 'rara supprimé : ' || (not exists (select 1 from public.events where id = 8))::text, null, null, null;
