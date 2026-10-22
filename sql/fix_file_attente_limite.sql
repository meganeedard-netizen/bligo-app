-- File d'attente : limite atteinte au moment de « Préparer pour X » (22/10/2026)
-- ============================================================
-- Avant : si la personne attendue avait atteint sa limite de documents, la
-- commande était refusée, la personne sortie de la file sans message et le
-- livre remis en rayon. Maintenant finish_reshelve s'arrête et renvoie
-- limit_reached ; le logiciel propose « Passer à la personne suivante »
-- (p_skip_first_hold, la personne est prévenue) ou « Garder le livre de côté ».

drop function if exists public.finish_reshelve(bigint, bigint);

create or replace function public.finish_reshelve(
  p_loan_id bigint default null, p_reservation_id bigint default null, p_skip_first_hold boolean default false
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
  v_limit_error text;
  v_title text;
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

  -- Premier de la file. Si l'agent a choisi de le passer (limite atteinte),
  -- il est sorti de la file et prévenu, puis on regarde le suivant.
  select h.id, h.user_id into v_hold_id, v_hold_user from public.holds h
    where h.book_id = v_book_id and h.status = 'waiting'
    order by h.created_at limit 1;
  if p_skip_first_hold and v_hold_id is not null then
    select title into v_title from public.books where id = v_book_id;
    update public.holds set status = 'skipped' where id = v_hold_id;
    insert into public.notifications (user_id, message)
    values (v_hold_user, '« ' || coalesce(v_title, '') || ' » que tu attendais est revenu, mais tu as atteint le nombre maximum de documents : il passe à la personne suivante. Rapporte un livre pour pouvoir en emprunter un autre.');
    select h.id, h.user_id into v_hold_id, v_hold_user from public.holds h
      where h.book_id = v_book_id and h.status = 'waiting'
      order by h.created_at limit 1;
  end if;

  -- Limite atteinte (22/10/2026) : rien ne bouge, l'agent choisit (passer au
  -- suivant ou garder le livre de côté). Avant, la personne était sortie de
  -- la file en silence et le livre remis en rayon.
  if v_hold_user is not null then
    v_limit_error := public.loan_limit_error(v_hold_user, v_book_id);
    if v_limit_error is not null then
      select full_name into v_name from public.profiles where id = v_hold_user;
      return jsonb_build_object('ok', false, 'limit_reached', true, 'hold_name', coalesce(v_name, 'L''usager'),
        'message', coalesce(v_name, 'L''usager') || ' ne peut pas recevoir ce livre : ' || v_limit_error);
    end if;
  end if;

  if v_hold_user is not null and v_copy_id is not null and v_copy_status in ('reserved', 'available') then
    if public.promote_next_hold(v_copy_id) then
      select p.full_name into v_name
      from public.holds h join public.profiles p on p.id = h.user_id
      where h.book_id = v_book_id and h.status = 'promoted'
      order by h.promoted_at desc limit 1;
      if p_loan_id is not null then
        update public.loans set reshelved = true where id = p_loan_id;
      else
        update public.reservations set reshelved = true where id = p_reservation_id;
      end if;
      return jsonb_build_object('ok', true, 'prepared_for', coalesce(v_name, 'l''usager'),
        'message', 'Commande prête pour ' || coalesce(v_name, 'l''usager') || ' : laisse le livre de côté, l''usager est prévenu et a 48 h pour venir le chercher.');
    end if;
  end if;

  if v_copy_id is not null and v_copy_status = 'reserved' then
    update public.book_copies set status = 'available' where id = v_copy_id;
  end if;

  if p_loan_id is not null then
    update public.loans set reshelved = true where id = p_loan_id;
  else
    update public.reservations set reshelved = true where id = p_reservation_id;
  end if;

  return jsonb_build_object('ok', true, 'prepared_for', null, 'message', 'Livre remis en rayon et de nouveau disponible en ligne.');
end;
$$;

grant execute on function public.finish_reshelve(bigint, bigint, boolean) to authenticated;

-- Vérification : doit renvoyer finish_reshelve avec 3 paramètres.
select proname, pg_get_function_identity_arguments(oid) from pg_proc where proname = 'finish_reshelve';
