-- File d'attente : l'agent attribue le livre en un clic depuis « À remettre en rayon » (19/10/2026)
-- ============================================================
-- Avant : à la fin des 48 h, le livre redevenait disponible en ligne tout de
-- suite (et la tâche automatique d'août ne gérait ni les exemplaires ni la
-- file d'attente) ; un livre rendu ou expiré était attribué en silence au
-- premier de la file, alors qu'il apparaissait quand même dans « À remettre
-- en rayon ».
--
-- Maintenant (demande de Mégane) :
--   - commande non récupérée sous 48 h : elle expire, le livre arrive dans
--     « À remettre en rayon » et reste HORS LIGNE jusqu'au clic de l'agent ;
--   - livre rendu alors que quelqu'un l'attend : il reste mis de côté (hors
--     ligne), sans attribution automatique ;
--   - dans « À remettre en rayon », la ligne affiche « Attendu par X » et le
--     bouton « Préparer pour X » : la commande passe « prête » chez X, qui est
--     prévenu dans l'appli et par e-mail. Sinon « Remis en rayon » remet le
--     livre en ligne.
-- ============================================================

-- 1. Livre rendu alors qu'un usager l'attend : il reste mis de côté.
create or replace function public.trg_hold_return_awaits_agent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'borrowed' and new.status = 'available'
    and exists (select 1 from public.holds where book_id = new.book_id and status = 'waiting') then
    new.status := 'reserved';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_hold_return_awaits_agent on public.book_copies;
create trigger trg_hold_return_awaits_agent
  before update of status on public.book_copies
  for each row execute function public.trg_hold_return_awaits_agent();

-- 2. Fin des 48 h (tâche automatique) : la commande expire, le livre reste hors ligne.
create or replace function public.expire_old_reservations()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cutoff_48h timestamptz := now() - interval '48 hours';
  cutoff_24h timestamptz := now() - interval '24 hours';
begin
  insert into public.notifications (user_id, message)
  select r.user_id, 'Il te reste 24h pour récupérer « ' || b.title || ' » avant qu''il ne reparte en rayon.'
  from public.reservations r
  join public.books b on b.id = r.book_id
  where r.status = 'pret'
    and r.ready_at <= cutoff_24h
    and r.notified_24h = false;

  update public.reservations
  set notified_24h = true
  where status = 'pret' and ready_at <= cutoff_24h and notified_24h = false;

  update public.reservations
  set status = 'expiree', reshelved = false
  where status = 'pret' and ready_at < cutoff_48h;
end;
$$;

do $$
begin
  perform cron.unschedule('expire-reservations');
exception when others then null;
end $$;
select cron.schedule('expire-reservations', '*/15 * * * *', $$select public.expire_old_reservations();$$);

-- 3. Même chose quand le logiciel constate l'expiration.
create or replace function public.expire_reservation(p_reservation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  update public.reservations set status = 'expiree', reshelved = false
    where id = p_reservation_id and status = 'pret';
  return jsonb_build_object('ok', found);
end;
$$;

grant execute on function public.expire_reservation(bigint) to authenticated;

-- 4. Clic de l'agent dans « À remettre en rayon » (un prêt rendu OU une
--    commande expirée). Si quelqu'un attend le livre, il lui est attribué
--    (commande prête + notification + e-mail, via promote_next_hold) ;
--    sinon le livre est remis en ligne.
create or replace function public.finish_reshelve(
  p_loan_id bigint default null, p_reservation_id bigint default null
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

  select h.user_id into v_hold_user from public.holds h
    where h.book_id = v_book_id and h.status = 'waiting'
    order by h.created_at limit 1;

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

grant execute on function public.finish_reshelve(bigint, bigint) to authenticated;

-- 5. E-mail « Ton livre est arrivé » au tutoiement (il part maintenant à chaque
--    « Préparer pour X ») ; le reste de la fonction est inchangé.
create or replace function public.promote_next_hold(p_copy_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_hold public.holds;
  v_reservation_id bigint;
  v_title text;
  v_email text;
  v_name text;
begin
  select * into v_copy from public.book_copies where id = p_copy_id;
  if v_copy.id is null then
    return false;
  end if;
  select title into v_title from public.books where id = v_copy.book_id;

  for v_hold in
    select * from public.holds where book_id = v_copy.book_id and status = 'waiting' order by created_at
  loop
    begin
      insert into public.reservations (user_id, book_id, status, pickup_commune_id)
      values (v_hold.user_id, v_copy.book_id, 'preparation', v_copy.current_commune_id)
      returning id into v_reservation_id;

      update public.book_copies set status = 'reserved' where id = v_copy.id;
      update public.reservations set status = 'pret' where id = v_reservation_id;
      update public.holds set status = 'promoted', reservation_id = v_reservation_id, promoted_at = now() where id = v_hold.id;

      select u.email, p.full_name into v_email, v_name
      from auth.users u left join public.profiles p on p.id = u.id where u.id = v_hold.user_id;
      if v_email is not null and to_regclass('public.email_outbox') is not null then
        insert into public.email_outbox (to_email, to_name, subject, body_text)
        values (v_email, v_name, 'Ton livre est arrivé : « ' || coalesce(v_title, '') || ' »',
          'Bonjour' || coalesce(' ' || v_name, '') || E',\n\nLe livre « ' || coalesce(v_title, '') ||
          E' » que tu attendais est revenu : il est mis de côté pour toi à la Médiathèque Municipale.\n' ||
          E'Tu as 48 heures pour venir le chercher, passé ce délai il sera proposé à la personne suivante.\n\nÀ bientôt,\nTa Médiathèque Municipale');
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
$$;

-- Vérification : les 5 fonctions doivent apparaître.
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('finish_reshelve', 'expire_reservation', 'expire_old_reservations', 'trg_hold_return_awaits_agent', 'promote_next_hold');
