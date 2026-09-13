-- Ajoute 15 livres "lus" (Click & Collect récupérés) sur ton compte
-- (megane.edard@hotmail.fr), pour montrer l'évolution du compte aux agents
-- de mairie. Les points de fidélité et les badges se mettent à jour
-- automatiquement via les triggers déjà en place (rien à faire d'autre).

do $$
declare
  v_user_id uuid;
  v_new_ids bigint[];
begin
  select id into v_user_id from auth.users where email = 'megane.edard@hotmail.fr';

  if v_user_id is null then
    raise exception 'Aucun compte trouvé pour l''adresse megane.edard@hotmail.fr — vérifie l''e-mail utilisé à l''inscription dans BliGO.';
  end if;

  with inserted as (
    insert into public.reservations (user_id, book_id, status)
    select v_user_id, b.id, 'preparation'
    from (select id from public.books order by id limit 15) b
    returning id
  )
  select array_agg(id) into v_new_ids from inserted;

  -- Passe les réservations à "récupéré" pour déclencher les points de
  -- fidélité (+10 chacune) et la vérification automatique des badges.
  update public.reservations
  set status = 'recupere'
  where id = any(v_new_ids);
end $$;
