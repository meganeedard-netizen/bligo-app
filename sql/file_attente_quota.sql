-- File d'attente et maximum de documents (22/10/2026, décisions de Mégane)
-- ============================================================
-- 1. Usager déjà à son maximum : il ne peut pas rejoindre la file d'attente,
--    on lui propose la liste d'envie (appli et comptoir).
-- 2. Usager entré dans la file AVANT d'atteindre son maximum : le livre lui
--    est quand même mis de côté (plus de « skipped » en silence), avec le
--    message « Bonne nouvelle… pense à rapporter un livre en venant ».
-- 3. Au comptoir, sa commande ne lui est remise qu'après le retour d'un livre.
-- Remplace le pop-up « Limite atteinte » côté agent (fix_file_attente_limite.sql).

drop function if exists public.loan_limit_error(uuid, bigint);

create or replace function public.loan_limit_error(p_user_id uuid, p_book_id bigint, p_already_counted boolean default false)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_category text;
  v_is_new boolean;
  v_is_jeunesse boolean;
  v_tariff text;
  v_commune public.communes;
  v_max integer;
  v_max_new integer;
  v_count integer;
  v_new_count integer;
  -- Livre déjà compté (sa propre commande) : la limite n'est dépassée qu'au-delà.
  v_extra integer := case when p_already_counted then 1 else 0 end;
begin
  select category, coalesce(is_new_release, false) into v_category, v_is_new from public.books where id = p_book_id;
  v_is_jeunesse := coalesce(v_category = 'Jeunesse', false);
  select tariff_category into v_tariff from public.profiles where id = p_user_id;
  select c.* into v_commune from public.communes c join public.profiles p on p.commune_id = c.id where p.id = p_user_id;

  if v_tariff = 'famille' then
    v_max := case when v_is_jeunesse then coalesce(v_commune.family_max_jeunesse, 10) else coalesce(v_commune.family_max_general, 10) end;
  else
    v_max := case when v_is_jeunesse then coalesce(v_commune.max_loans_jeunesse, 3) else coalesce(v_commune.max_loans_general, 3) end;
  end if;
  v_max_new := coalesce(v_commune.max_loans_new_releases, 1);

  select
    (select count(*) from public.reservations r join public.books b on b.id = r.book_id
      where r.user_id = p_user_id and r.status in ('panier', 'preparation', 'pret')
        and coalesce(b.category = 'Jeunesse', false) = v_is_jeunesse)
    + (select count(*) from public.loans l join public.book_copies c on c.id = l.copy_id join public.books b on b.id = c.book_id
        where l.user_id = p_user_id and l.returned_at is null
          and coalesce(b.category = 'Jeunesse', false) = v_is_jeunesse)
  into v_count;

  if v_count >= v_max + v_extra then
    if v_tariff = 'famille' then
      return format('Limite de la carte famille atteinte : %s documents %s maximum à la fois.', v_max, case when v_is_jeunesse then 'jeunesse' else 'adultes' end);
    elsif v_is_jeunesse then
      return format('Limite atteinte : %s documents jeunesse maximum à la fois.', v_max);
    else
      return format('Limite atteinte : %s documents maximum à la fois.', v_max);
    end if;
  end if;

  if v_is_new then
    select
      (select count(*) from public.reservations r join public.books b on b.id = r.book_id
        where r.user_id = p_user_id and r.status in ('panier', 'preparation', 'pret') and coalesce(b.is_new_release, false))
      + (select count(*) from public.loans l join public.book_copies c on c.id = l.copy_id join public.books b on b.id = c.book_id
          where l.user_id = p_user_id and l.returned_at is null and coalesce(b.is_new_release, false))
    into v_new_count;
    if v_new_count >= v_max_new + v_extra then
      return format('Limite atteinte : %s nouveauté(s) maximum à la fois.', v_max_new);
    end if;
  end if;

  return null;
end;
$$;

grant execute on function public.loan_limit_error(uuid, bigint, boolean) to authenticated;

create or replace function public.enforce_reservation_limits()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_category text;
  v_is_new_release boolean := false;
  v_is_jeunesse boolean;
  v_adult_only boolean := false;
  v_active_count integer;
  v_new_release_count integer;
  v_user_commune bigint;
  v_flagged boolean;
  v_tariff_category text;
  v_max_general integer;
  v_max_jeunesse integer;
  v_max_new_release integer;
  v_restricted_categories text[];
  v_blocks_new_release boolean;
  v_limit_error text;
begin
  -- Livre mis de côté pour la file d'attente (22/10/2026) : la personne y était
  -- avant d'atteindre sa limite ; elle rapportera un livre en venant le chercher.
  if current_setting('bligo.hold_promotion', true) = 'on' then
    return new;
  end if;

  if tg_table_name = 'reservations' then
    select category, coalesce(is_new_release, false), coalesce(adult_only, false)
    into v_category, v_is_new_release, v_adult_only
    from public.books where id = new.book_id;

    -- Même livre déjà dans le panier, en commande ou chez l'usager.
    if exists (
      select 1 from public.reservations r
      where r.user_id = new.user_id and r.book_id = new.book_id
        and r.status in ('panier', 'preparation', 'pret')
    ) or exists (
      select 1 from public.loans l join public.book_copies c on c.id = l.copy_id
      where l.user_id = new.user_id and c.book_id = new.book_id and l.returned_at is null
    ) then
      raise exception 'Tu as déjà ce livre dans ton panier, ta commande ou chez toi.';
    end if;
  else
    select category into v_category from public.free_books where id = new.free_book_id;
  end if;

  v_is_jeunesse := (v_category = 'Jeunesse');

  select commune_id, coalesce(flagged, false), tariff_category
  into v_user_commune, v_flagged, v_tariff_category
  from public.profiles where id = new.user_id;

  if v_tariff_category = 'mineur' and v_adult_only then
    raise exception 'Ce livre est réservé aux comptes majeurs.';
  end if;

  select
    coalesce(max_loans_general, 3), coalesce(max_loans_jeunesse, 3), coalesce(max_loans_new_releases, 1),
    coalesce(flagged_restricted_categories, '{}'), coalesce(flagged_blocks_new_releases, true)
  into v_max_general, v_max_jeunesse, v_max_new_release, v_restricted_categories, v_blocks_new_release
  from public.communes where id = v_user_commune;

  v_max_general := coalesce(v_max_general, 3);
  v_max_jeunesse := coalesce(v_max_jeunesse, 3);
  v_max_new_release := coalesce(v_max_new_release, 1);
  v_restricted_categories := coalesce(v_restricted_categories, '{}');
  v_blocks_new_release := coalesce(v_blocks_new_release, true);

  if v_flagged and v_category = any(v_restricted_categories) then
    raise exception 'Cet usager est actuellement restreint et ne peut pas emprunter dans la catégorie « % ».', v_category;
  end if;

  if v_flagged and v_blocks_new_release and v_is_new_release then
    raise exception 'Cet usager est actuellement restreint et ne peut pas emprunter les nouveautés.';
  end if;

  -- Carte famille (22/10/2026) : un plafond pour les documents adultes et un
  -- pour les documents jeunesse, réglés par la médiathèque.
  if v_tariff_category = 'famille' and tg_table_name = 'reservations' then
    v_limit_error := public.loan_limit_error(new.user_id, new.book_id);
    if v_limit_error is not null then
      raise exception '%', v_limit_error;
    end if;
    return new;
  end if;

  if tg_table_name = 'reservations' then
    select
      (select count(*)
         from public.reservations r
         join public.books b on b.id = r.book_id
        where r.user_id = new.user_id and r.status in ('panier', 'preparation', 'pret')
          and coalesce(b.category = 'Jeunesse', false) = coalesce(v_is_jeunesse, false))
      + (select count(*)
           from public.loans l
           join public.book_copies c on c.id = l.copy_id
           join public.books b on b.id = c.book_id
          where l.user_id = new.user_id and l.returned_at is null
            and coalesce(b.category = 'Jeunesse', false) = coalesce(v_is_jeunesse, false))
    into v_active_count;
  else
    select count(*) into v_active_count
    from public.free_book_loans l
    join public.free_books fb on fb.id = l.free_book_id
    where l.user_id = new.user_id and l.status in ('preparation', 'pret')
      and coalesce(fb.category = 'Jeunesse', false) = coalesce(v_is_jeunesse, false);
  end if;

  if v_is_jeunesse then
    if v_active_count >= v_max_jeunesse then
      raise exception 'Limite atteinte : % documents jeunesse maximum à la fois (panier, commande et emprunts compris).', v_max_jeunesse;
    end if;
  elsif tg_table_name = 'reservations' then
    if v_active_count >= v_max_general then
      raise exception 'Limite atteinte : % documents maximum à la fois (panier, commande et emprunts compris).', v_max_general;
    end if;
  else
    if v_active_count >= v_max_general then
      raise exception 'Limite atteinte : % livres hors condition maximum en cours à la fois (hors jeunesse). Rapporte-en un pour en prendre un nouveau.', v_max_general;
    end if;
  end if;

  if v_is_new_release and tg_table_name = 'reservations' then
    select
      (select count(*)
         from public.reservations r
         join public.books b on b.id = r.book_id
        where r.user_id = new.user_id and r.status in ('panier', 'preparation', 'pret') and coalesce(b.is_new_release, false))
      + (select count(*)
           from public.loans l
           join public.book_copies c on c.id = l.copy_id
           join public.books b on b.id = c.book_id
          where l.user_id = new.user_id and l.returned_at is null and coalesce(b.is_new_release, false))
    into v_new_release_count;

    if v_new_release_count >= v_max_new_release then
      raise exception 'Limite atteinte : % nouveauté(s) maximum à la fois.', v_max_new_release;
    end if;
  end if;

  return new;
end;
$$;

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
  v_over_limit boolean;
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
        values (v_hold.user_id, 'Bonne nouvelle : « ' || coalesce(v_title, '') || ' » est arrivé ! Il t''attend 48 h à la Médiathèque Municipale. Tu as atteint ton maximum d''emprunts : pense à rapporter un livre en venant le chercher.');
      end if;
      update public.holds set status = 'promoted', reservation_id = v_reservation_id, promoted_at = now() where id = v_hold.id;

      select u.email, p.full_name into v_email, v_name
      from auth.users u left join public.profiles p on p.id = u.id where u.id = v_hold.user_id;
      if v_email is not null and to_regclass('public.email_outbox') is not null then
        insert into public.email_outbox (to_email, to_name, subject, body_text)
        values (v_email, v_name, 'Ton livre est arrivé : « ' || coalesce(v_title, '') || ' »',
          case when v_over_limit then
            'Bonjour' || coalesce(' ' || v_name, '') || E',\n\nBonne nouvelle : « ' || coalesce(v_title, '') ||
            E' » est arrivé ! Il t''attend 48 heures à la Médiathèque Municipale.\n' ||
            E'Tu as atteint ton maximum d''emprunts : pense à rapporter un livre en venant le chercher.\n\nÀ bientôt,\nTa Médiathèque Municipale'
          else
            'Bonjour' || coalesce(' ' || v_name, '') || E',\n\nLe livre « ' || coalesce(v_title, '') ||
            E' » que tu attendais est revenu : il est mis de côté pour toi à la Médiathèque Municipale.\n' ||
            E'Tu as 48 heures pour venir le chercher, passé ce délai il sera proposé à la personne suivante.\n\nÀ bientôt,\nTa Médiathèque Municipale'
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
$$;

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

create or replace function public.join_hold(p_book_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_book public.books;
  v_status text;
  v_position integer;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;
  select * into v_book from public.books where id = p_book_id;
  if v_book.id is null then
    return jsonb_build_object('ok', false, 'message', 'Livre introuvable.');
  end if;
  if coalesce(v_book.on_site_only, false) then
    return jsonb_build_object('ok', false, 'message', 'Ce document se consulte uniquement sur place.');
  end if;
  -- Un exemplaire en rayon déjà promis à une commande ne compte pas comme libre.
  if public.free_copies_count(p_book_id) > 0 then
    return jsonb_build_object('ok', false, 'message', 'Ce livre est disponible : tu peux le réserver directement.');
  end if;
  if exists (select 1 from public.reservations where book_id = p_book_id and user_id = auth.uid() and status in ('preparation', 'pret'))
    or exists (select 1 from public.loans l join public.book_copies c on c.id = l.copy_id
               where c.book_id = p_book_id and l.user_id = auth.uid() and l.returned_at is null) then
    return jsonb_build_object('ok', false, 'message', 'Tu as déjà ce livre en réservation ou en prêt.');
  end if;

  v_status := public.membership_status(auth.uid(), v_book.commune_id);
  if v_status <> 'ok' then
    return jsonb_build_object('ok', false, 'message', public.membership_error_message(v_status));
  end if;

  -- Déjà à son maximum (22/10/2026) : pas de file d'attente, la liste d'envie.
  if public.loan_limit_error(auth.uid(), p_book_id) is not null then
    return jsonb_build_object('ok', false, 'limit_reached', true,
      'message', 'Tu as atteint le nombre maximum de livres pour ta médiathèque. Ajoute-le à ta liste d''envie : tu seras prévenu(e) dès son retour.');
  end if;

  insert into public.holds (book_id, user_id) values (p_book_id, auth.uid())
  on conflict do nothing;

  select count(*) into v_position from public.holds
  where book_id = p_book_id and status = 'waiting'
    and created_at <= (select created_at from public.holds where book_id = p_book_id and user_id = auth.uid() and status = 'waiting');

  return jsonb_build_object('ok', true, 'position', v_position,
    'message', 'Tu es n° ' || v_position || ' dans la file d''attente. Tu seras prévenu(e) dès que le livre sera mis de côté pour toi.');
end;
$$;

create or replace function public.agent_join_hold(p_book_id bigint, p_subscriber_number text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_book public.books;
  v_user uuid;
  v_name text;
  v_status text;
  v_position integer;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select id, full_name into v_user, v_name from public.profiles
   where subscriber_number = trim(p_subscriber_number);
  if v_user is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun usager ne porte ce numéro d''abonné.');
  end if;
  v_name := coalesce(v_name, 'L''usager');

  select * into v_book from public.books where id = p_book_id;
  if v_book.id is null then
    return jsonb_build_object('ok', false, 'message', 'Livre introuvable.');
  end if;
  if coalesce(v_book.on_site_only, false) then
    return jsonb_build_object('ok', false, 'message', 'Ce document se consulte uniquement sur place.');
  end if;
  -- Un exemplaire en rayon déjà promis à une commande ne compte pas comme libre.
  if public.free_copies_count(p_book_id) > 0 then
    return jsonb_build_object('ok', false, 'message', 'Un exemplaire est disponible en rayon : prête-le directement.');
  end if;
  if exists (select 1 from public.reservations where book_id = p_book_id and user_id = v_user and status in ('preparation', 'pret'))
    or exists (select 1 from public.loans l join public.book_copies c on c.id = l.copy_id
               where c.book_id = p_book_id and l.user_id = v_user and l.returned_at is null) then
    return jsonb_build_object('ok', false, 'message', v_name || ' a déjà ce livre en commande ou en prêt.');
  end if;

  v_status := public.membership_status(v_user, v_book.commune_id);
  if v_status <> 'ok' then
    return jsonb_build_object('ok', false, 'message', public.membership_error_message(v_status));
  end if;

  -- Déjà à son maximum (22/10/2026) : pas de file d'attente.
  if public.loan_limit_error(v_user, p_book_id) is not null then
    return jsonb_build_object('ok', false, 'limit_reached', true,
      'message', v_name || ' a atteint son maximum de documents : pas de file d''attente possible. Propose-lui d''ajouter le livre à sa liste d''envie dans l''appli, il sera prévenu à son retour.');
  end if;

  insert into public.holds (book_id, user_id) values (p_book_id, v_user)
  on conflict do nothing;

  select count(*) into v_position from public.holds
  where book_id = p_book_id and status = 'waiting'
    and created_at <= (select created_at from public.holds where book_id = p_book_id and user_id = v_user and status = 'waiting');

  insert into public.notifications (user_id, message)
  values (v_user, 'Tu es n° ' || v_position || ' dans la file d''attente pour « ' || v_book.title || ' ». Tu seras prévenu(e) dès que le livre sera mis de côté pour toi.');

  return jsonb_build_object('ok', true, 'position', v_position, 'name', v_name,
    'message', v_name || ' est n° ' || v_position || ' dans la file d''attente. Prévenu(e) dès que le livre sera mis de côté.');
end;
$$;

create or replace function public.counter_checkout(p_barcode text, p_subscriber_number text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_user uuid;
  v_resa bigint;
  v_others integer;
  v_reserved integer;
  v_free integer;
  v_result jsonb;
  v_loan bigint;
  v_limit_error text;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_copy from public.book_copies where barcode = trim(p_barcode);
  select id into v_user from public.profiles where subscriber_number = trim(p_subscriber_number);
  -- Code-barres ou usager inconnu : scan_checkout renvoie le bon message.
  if v_copy.id is null or v_user is null then
    return public.scan_checkout(p_barcode, p_subscriber_number);
  end if;

  -- Commande de cet usager pour ce livre (en préparation ou prête).
  select r.id into v_resa from public.reservations r
   where r.book_id = v_copy.book_id and r.user_id = v_user and r.status in ('preparation', 'pret')
   order by r.created_at limit 1;

  -- Exemplaire en rayon, mais tous les exemplaires libres sont promis à des
  -- commandes d'autres usagers (les exemplaires déjà mis de côté couvrent
  -- chacun une commande).
  if v_resa is null and v_copy.status = 'available' then
    select count(*) into v_others from public.reservations r
     where r.book_id = v_copy.book_id and r.user_id <> v_user and r.status in ('preparation', 'pret');
    select count(*) into v_reserved from public.book_copies where book_id = v_copy.book_id and status = 'reserved';
    select count(*) into v_free from public.book_copies where book_id = v_copy.book_id and status = 'available';
    if v_others - v_reserved >= v_free then
      return jsonb_build_object('ok', false, 'ordered_by_other', true,
        'message', 'Ce livre est commandé par un autre usager dans l''appli (commande en préparation ou prête) : il ne peut pas être prêté.');
    end if;
  end if;

  -- Limites de la médiathèque (22/10/2026) : documents adultes, jeunesse,
  -- nouveautés, et plafonds propres à la carte famille. Le livre qu'il avait
  -- déjà commandé est déjà compté.
  if v_resa is null then
    v_limit_error := public.loan_limit_error(v_user, v_copy.book_id);
    if v_limit_error is not null then
      return jsonb_build_object('ok', false, 'limit_reached', true, 'message', v_limit_error);
    end if;
  else
    -- Sa commande (souvent un livre de la file d'attente) alors qu'il est à son
    -- maximum : un retour d'abord (22/10/2026).
    if public.loan_limit_error(v_user, v_copy.book_id, true) is not null then
      return jsonb_build_object('ok', false, 'limit_reached', true,
        'message', 'Sa commande l''attend, mais il a atteint son maximum de documents : enregistre d''abord le retour d''un livre (Comptoir › Retour).');
    end if;
  end if;

  v_result := public.scan_checkout(p_barcode, p_subscriber_number);

  -- Prêt du livre qu'il avait commandé : la commande est récupérée.
  if coalesce((v_result->>'ok')::boolean, false) and v_resa is not null then
    select id into v_loan from public.loans
     where copy_id = v_copy.id and returned_at is null order by borrowed_at desc limit 1;
    update public.loans set reservation_id = v_resa where id = v_loan and reservation_id is null;
    update public.reservations
       set status = 'recupere', return_due_at = coalesce((v_result->>'due_at')::timestamptz, return_due_at)
     where id = v_resa and status in ('preparation', 'pret');
    v_result := v_result || jsonb_build_object('from_reservation', true);
  end if;

  return v_result;
end;
$$;

-- Vérification : doit renvoyer les 6 fonctions.
select proname, pg_get_function_identity_arguments(oid) as parametres from pg_proc
 where proname in ('loan_limit_error', 'enforce_reservation_limits', 'promote_next_hold', 'finish_reshelve', 'join_hold', 'agent_join_hold', 'counter_checkout')
 order by proname;
