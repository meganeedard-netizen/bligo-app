-- Délai de retrait réglable par médiathèque (03/11/2026, demande de Mégane).
-- Avant : 48 h codées en dur. Désormais communes.pickup_hours (48 par défaut),
-- réglé par la direction dans le logiciel (Réglages > Tarifs et conditions).
-- Chaque réservation prête garde sa date limite (reservations.pickup_deadline),
-- calculée au moment où elle devient prête : changer le réglage ne modifie pas
-- les réservations déjà prêtes. L'appli usager lit cette date.
-- Fonctions reprises de leur version en ligne du 03/11/2026, seuls les 48 h changent.

alter table public.communes add column if not exists pickup_hours integer not null default 48;
alter table public.communes drop constraint if exists communes_pickup_hours_check;
alter table public.communes add constraint communes_pickup_hours_check check (pickup_hours between 24 and 336);
alter table public.reservations add column if not exists pickup_deadline timestamptz;

-- Médiathèque qui remet le livre : lieu de retrait, sinon celle du livre.
create or replace function public.reservation_commune_id(p_pickup_commune_id bigint, p_book_id bigint)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(p_pickup_commune_id, (select commune_id from public.books where id = p_book_id));
$$;

create or replace function public.pickup_hours_for(p_commune_id bigint)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce((select pickup_hours from public.communes where id = p_commune_id), 48);
$$;

-- « 48 h », « 3 jours »… pour les messages.
create or replace function public.pickup_delay_label(p_commune_id bigint)
returns text language sql stable security definer set search_path = public as $$
  select case when h >= 72 and h % 24 = 0 then (h / 24)::text || ' jours' else h::text || ' h' end
  from (select public.pickup_hours_for(p_commune_id) as h) x;
$$;

-- Date limite posée dès que la réservation a sa date « prête ».
create or replace function public.set_pickup_deadline()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.ready_at is not null and (tg_op = 'INSERT' or new.ready_at is distinct from old.ready_at or new.pickup_deadline is null) then
    new.pickup_deadline := new.ready_at
      + make_interval(hours => public.pickup_hours_for(public.reservation_commune_id(new.pickup_commune_id, new.book_id)));
  end if;
  return new;
end;
$$;
drop trigger if exists trg_set_pickup_deadline on public.reservations;
create trigger trg_set_pickup_deadline before insert or update of ready_at, status on public.reservations
  for each row execute function public.set_pickup_deadline();

-- Réservations déjà prêtes : elles gardent leurs 48 h.
update public.reservations set pickup_deadline = ready_at + interval '48 hours'
where status = 'pret' and ready_at is not null and pickup_deadline is null;

-- Réglage par la direction de la médiathèque.
create or replace function public.update_commune_pickup_hours(p_commune_id bigint, p_hours integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;
  if p_hours is null or p_hours < 24 or p_hours > 336 then
    raise exception 'Délai entre 24 h et 14 jours';
  end if;
  update public.communes set pickup_hours = p_hours where id = p_commune_id;
  perform public.log_activity('pickup_hours_changed', p_commune_id, 'commune', p_commune_id::text,
    jsonb_build_object('hours', p_hours));
end;
$$;
revoke all on function public.update_commune_pickup_hours(bigint, integer) from public, anon;
grant execute on function public.update_commune_pickup_hours(bigint, integer) to authenticated;

CREATE OR REPLACE FUNCTION public.expire_old_reservations()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Rappel 24 h avant la fin du délai de retrait, seulement si ce délai
  -- dépasse 24 h (sinon le rappel arriverait en même temps que l'avis « prêt »).
  insert into public.notifications (user_id, message)
  select r.user_id, 'Il te reste 24h pour récupérer « ' || b.title || ' » avant qu''il ne reparte en rayon.'
  from public.reservations r
  join public.books b on b.id = r.book_id
  where r.status = 'pret'
    and r.notified_24h = false
    and coalesce(r.pickup_deadline, r.ready_at + interval '48 hours') - r.ready_at > interval '24 hours'
    and now() >= coalesce(r.pickup_deadline, r.ready_at + interval '48 hours') - interval '24 hours';

  update public.reservations r
  set notified_24h = true
  where r.status = 'pret' and r.notified_24h = false
    and now() >= coalesce(r.pickup_deadline, r.ready_at + interval '48 hours') - interval '24 hours';

  update public.reservations r
  set status = 'expiree', reshelved = false
  where r.status = 'pret' and now() > coalesce(r.pickup_deadline, r.ready_at + interval '48 hours');
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_on_ready()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_title text;
begin
  if new.status = 'pret' and old.status is distinct from 'pret' then
    select title into v_title from public.books where id = new.book_id;
    insert into public.notifications (user_id, message)
    values (new.user_id, 'Ta réservation « ' || coalesce(v_title, '') || ' » est prête ! Tu as '
      || public.pickup_delay_label(public.reservation_commune_id(new.pickup_commune_id, new.book_id))
      || ' pour venir la chercher à la médiathèque.');
    update public.reservations set ready_at = now() where id = new.id;
  end if;

  if new.status = 'recupere' and old.status is distinct from 'recupere' then
    select title into v_title from public.books where id = new.book_id;
    update public.reservations set return_due_at = now() + interval '21 days' where id = new.id;
    insert into public.notifications (user_id, message)
    values (new.user_id, 'Merci ! « ' || coalesce(v_title, '') || ' » est à rapporter à la médiathèque avant le ' || to_char((now() + interval '21 days'), 'DD/MM/YYYY') || '.');
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.promote_next_hold(p_copy_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_copy public.book_copies;
  v_hold public.holds;
  v_reservation_id bigint;
  v_title text;
  v_email text;
  v_name text;
  v_over_limit boolean;
  v_delai text;
begin
  select * into v_copy from public.book_copies where id = p_copy_id;
  if v_copy.id is null then
    return false;
  end if;
  select title into v_title from public.books where id = v_copy.book_id;
  v_delai := public.pickup_delay_label(v_copy.current_commune_id);

  for v_hold in
    select * from public.holds where book_id = v_copy.book_id and status = 'waiting' order by created_at
  loop
    begin
      -- Déjà à son maximum (il a emprunté d'autres livres en attendant) : le
      -- livre lui est quand même mis de côté, avec un message pour qu'il en
      -- rapporte un en venant (22/10/2026).
      v_over_limit := public.loan_limit_error(v_hold.user_id, v_copy.book_id) is not null;
      perform set_config('bligo.hold_promotion', 'on', true);
      insert into public.reservations (user_id, book_id, status, pickup_commune_id)
      values (v_hold.user_id, v_copy.book_id, 'preparation', v_copy.current_commune_id)
      returning id into v_reservation_id;
      perform set_config('bligo.hold_promotion', 'off', true);

      update public.book_copies set status = 'reserved' where id = v_copy.id;
      update public.reservations set status = 'pret' where id = v_reservation_id;
      if v_over_limit then
        insert into public.notifications (user_id, message)
        values (v_hold.user_id, 'Bonne nouvelle : « ' || coalesce(v_title, '') || ' » est arrivé ! Il t''attend ' || v_delai || ' à la Médiathèque Municipale. Tu as atteint ton maximum d''emprunts : pense à rapporter un livre en venant le chercher.');
      end if;
      update public.holds set status = 'promoted', reservation_id = v_reservation_id, promoted_at = now() where id = v_hold.id;

      select u.email, p.full_name into v_email, v_name
      from auth.users u left join public.profiles p on p.id = u.id where u.id = v_hold.user_id;
      if v_email is not null and to_regclass('public.email_outbox') is not null then
        insert into public.email_outbox (to_email, to_name, subject, body_text)
        values (v_email, v_name, 'Ton livre est arrivé : « ' || coalesce(v_title, '') || ' »',
          case when v_over_limit then
            'Bonjour' || coalesce(' ' || v_name, '') || E',\n\nBonne nouvelle : « ' || coalesce(v_title, '') ||
            E' » est arrivé ! Il t''attend ' || v_delai || E' à la Médiathèque Municipale.\n' ||
            E'Tu as atteint ton maximum d''emprunts : pense à rapporter un livre en venant le chercher.\n\nÀ bientôt,\nTa Médiathèque Municipale'
          else
            'Bonjour' || coalesce(' ' || v_name, '') || E',\n\nLe livre « ' || coalesce(v_title, '') ||
            E' » que tu attendais est revenu : il est mis de côté pour toi à la Médiathèque Municipale.\n' ||
            E'Tu as ' || v_delai || E' pour venir le chercher, passé ce délai il sera proposé à la personne suivante.\n\nÀ bientôt,\nTa Médiathèque Municipale'
          end);
      end if;
      return true;
    exception when others then
      update public.holds set status = 'skipped' where id = v_hold.id;
      insert into public.notifications (user_id, message)
      values (v_hold.user_id, '« ' || coalesce(v_title, '') || ' » que tu attendais est revenu, mais il n''a pas pu être mis de côté pour toi (' || sqlerrm || '). Il passe à la personne suivante.');
    end;
  end loop;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION public.finish_reshelve(p_loan_id bigint DEFAULT NULL::bigint, p_reservation_id bigint DEFAULT NULL::bigint, p_skip_first_hold boolean DEFAULT false, p_keep_over_limit boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      'message', 'Commande prête pour ' || coalesce(v_name, 'l''usager') || ' : laisse le livre de côté, l''usager est prévenu et a ' || public.pickup_delay_label(public.agent_commune_id()) || ' pour venir le chercher.');
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
$function$;
