-- File d'attente et maximum : l'agent choisit (03/11/2026)
-- ============================================================
-- Cas vu par Mégane : un usager s'inscrit en file d'attente quand il a 0
-- livre, commande ensuite 3 livres (son maximum), puis le livre attendu
-- revient. « Préparer pour X » lui mettait le livre de côté sans rien dire
-- (4e livre).
--
-- Maintenant, au clic sur « Préparer pour X », si X a déjà son maximum :
--   - finish_reshelve répond limit_reached (rien ne bouge) et le logiciel
--     ouvre un pop-up ;
--   - « Passer à la personne suivante » (p_skip_first_hold) : le livre va au
--     suivant de la file, ou retourne en rayon s'il n'y a personne. X GARDE
--     SA PLACE en tête de file pour le prochain retour, et il est prévenu ;
--   - « Garder le livre de côté quand même » (p_keep_over_limit) : ancien
--     fonctionnement, mis de côté avec « pense à rapporter un livre », et le
--     Comptoir exige un retour avant de le remettre.
-- ============================================================

drop function if exists public.finish_reshelve(bigint, bigint, boolean);

create or replace function public.finish_reshelve(
  p_loan_id bigint default null, p_reservation_id bigint default null,
  p_skip_first_hold boolean default false, p_keep_over_limit boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_book_id bigint;
  v_commune bigint;
  v_copy_id bigint;
  v_copy_status text;
  v_reserved integer;
  v_active integer;
  v_hold_user uuid;
  v_name text;
  v_hold_id bigint;
  v_skipped_hold_id bigint;
  v_title text;
  v_result jsonb;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  if p_loan_id is not null then
    select c.id, c.book_id, c.status into v_copy_id, v_book_id, v_copy_status
    from public.loans l join public.book_copies c on c.id = l.copy_id
    where l.id = p_loan_id;
    if v_book_id is null then
      return jsonb_build_object('ok', false, 'message', 'Prêt introuvable.');
    end if;
  elsif p_reservation_id is not null then
    select book_id, pickup_commune_id into v_book_id, v_commune
    from public.reservations where id = p_reservation_id;
    if v_book_id is null then
      return jsonb_build_object('ok', false, 'message', 'Réservation introuvable.');
    end if;
    v_commune := coalesce(v_commune, public.agent_commune_id());

    -- L'exemplaire mis de côté pour cette commande : on ne prend un exemplaire
    -- « reserved » que s'il y en a plus que de commandes encore en cours,
    -- pour ne jamais libérer celui d'une autre commande.
    select count(*) into v_reserved from public.book_copies
      where book_id = v_book_id and status = 'reserved' and current_commune_id = v_commune;
    select count(*) into v_active from public.reservations
      where book_id = v_book_id and status in ('preparation', 'pret')
        and coalesce(pickup_commune_id, v_commune) = v_commune;
    if v_reserved > v_active then
      select id, status into v_copy_id, v_copy_status from public.book_copies
        where book_id = v_book_id and status = 'reserved' and current_commune_id = v_commune
        order by id limit 1;
    end if;
    -- Données d'avant ce correctif : l'exemplaire a déjà été remis disponible.
    if v_copy_id is null then
      select id, status into v_copy_id, v_copy_status from public.book_copies
        where book_id = v_book_id and status = 'available' and current_commune_id = v_commune
        order by id limit 1;
    end if;
  else
    return jsonb_build_object('ok', false, 'message', 'Rien à remettre en rayon.');
  end if;

  select title into v_title from public.books where id = v_book_id;
  select h.id, h.user_id into v_hold_id, v_hold_user from public.holds h
    where h.book_id = v_book_id and h.status = 'waiting'
    order by h.created_at limit 1;

  -- Premier de la file déjà à son maximum : on demande à l'agent.
  if v_hold_id is not null and not p_skip_first_hold and not p_keep_over_limit
    and public.loan_limit_error(v_hold_user, v_book_id) is not null then
    select full_name into v_name from public.profiles where id = v_hold_user;
    return jsonb_build_object('ok', false, 'limit_reached', true, 'name', coalesce(v_name, 'L''usager'),
      'message', coalesce(v_name, 'L''usager') || ' a déjà atteint son maximum de livres.');
  end if;

  -- « Passer à la personne suivante » : X est mis à l'écart le temps de ce
  -- traitement (ni promote_next_hold ni le déclencheur de retour ne le
  -- voient), puis remis en attente à la même place.
  if p_skip_first_hold and v_hold_id is not null then
    v_skipped_hold_id := v_hold_id;
    update public.holds set status = 'skipped' where id = v_skipped_hold_id;
    insert into public.notifications (user_id, message)
    values (v_hold_user, '« ' || coalesce(v_title, '') || ' » que tu attendais est revenu, mais tu as déjà ton maximum de livres : il a été proposé à la personne suivante. Tu gardes ta place dans la file d''attente : rapporte un livre pour pouvoir l''emprunter au prochain retour.');
    select h.id, h.user_id into v_hold_id, v_hold_user from public.holds h
      where h.book_id = v_book_id and h.status = 'waiting'
      order by h.created_at limit 1;
  end if;

  if v_hold_user is not null and v_copy_id is not null and v_copy_status in ('reserved', 'available')
    and public.promote_next_hold(v_copy_id) then
    select p.full_name into v_name
    from public.holds h join public.profiles p on p.id = h.user_id
    where h.book_id = v_book_id and h.status = 'promoted'
    order by h.promoted_at desc limit 1;
    v_result := jsonb_build_object('ok', true, 'prepared_for', coalesce(v_name, 'l''usager'),
      'message', 'Commande prête pour ' || coalesce(v_name, 'l''usager') || ' : laisse le livre de côté, l''usager est prévenu et a 48 h pour venir le chercher.');
  else
    if v_copy_id is not null and v_copy_status = 'reserved' then
      update public.book_copies set status = 'available' where id = v_copy_id;
    end if;
    v_result := jsonb_build_object('ok', true, 'prepared_for', null, 'message', 'Livre remis en rayon et de nouveau disponible en ligne.');
  end if;

  if v_skipped_hold_id is not null then
    update public.holds set status = 'waiting' where id = v_skipped_hold_id;
  end if;

  if p_loan_id is not null then
    update public.loans set reshelved = true where id = p_loan_id;
  else
    update public.reservations set reshelved = true where id = p_reservation_id;
  end if;

  return v_result;
end;
$$;

grant execute on function public.finish_reshelve(bigint, bigint, boolean, boolean) to authenticated;

-- Vérification : doit afficher une seule ligne, avec 4 paramètres.
select pg_get_function_identity_arguments(oid) from pg_proc where proname = 'finish_reshelve';

-- ============================================================
-- Nettoyage (03/11/2026) : « D'autres printemps » apparaissait à la fois dans
-- « Commandes prêtes » et dans « À remettre en rayon » alors qu'il n'a qu'un
-- exemplaire. Reste du bug de double commande corrigé le 28/10
-- (fix_double_reservation.sql) : deux commandes expirées sur le même
-- exemplaire attendaient chacune d'être remises en rayon. Une seule a été
-- traitée, l'autre est restée.
-- Règle : une commande expirée attend le rayon seulement s'il reste un
-- exemplaire mis de côté qui n'est promis à aucune commande en cours. Sinon
-- le livre est déjà en rayon ou déjà promis à quelqu'un.
-- ============================================================
update public.reservations r
set reshelved = true
where r.status = 'expiree' and not r.reshelved
  and (select count(*) from public.book_copies c where c.book_id = r.book_id and c.status = 'reserved')
   <= (select count(*) from public.reservations a where a.book_id = r.book_id and a.status in ('preparation', 'pret'));
