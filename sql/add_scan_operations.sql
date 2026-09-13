-- BliGO — Opérations de scan du back-office agents (13/09/2026)
-- Emprunt, retour, rangement en rayon, transferts.
--
-- Ces fonctions sont appelées à l'identique par la douchette USB branchée sur
-- l'ordinateur et par le scan depuis un smartphone ou une tablette : c'est la base
-- centrale qui tranche, pas l'appareil. Le statut d'un livre est donc le même
-- partout, en temps réel, quel que soit l'appareil qui a scanné.
--
-- Prérequis : add_copies_communities_loans.sql
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run


-- ============================================================
-- 1. Identifier un exemplaire au scan
-- ============================================================
-- Renvoie tout ce que l'agent doit voir à l'écran dès qu'il scanne un code-barres :
-- le livre, son état, sa cote, et qui l'a emprunté le cas échéant.

create or replace function public.scan_lookup(p_barcode text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select jsonb_build_object(
    'found', true,
    'copy_id', c.id,
    'barcode', c.barcode,
    'status', c.status,
    'shelf_location', c.shelf_location,
    'title', b.title,
    'author', b.author,
    'cover_url', b.cover_url,
    'isbn', b.isbn,
    'owner_commune', owner_c.name,
    'current_commune', current_c.name,
    'is_away_from_home', c.owner_commune_id <> c.current_commune_id,
    'borrower_name', p.full_name,
    'borrower_number', p.subscriber_number,
    'due_at', l.due_at
  )
  into result
  from public.book_copies c
  join public.books b on b.id = c.book_id
  join public.communes owner_c on owner_c.id = c.owner_commune_id
  join public.communes current_c on current_c.id = c.current_commune_id
  left join public.loans l on l.copy_id = c.id and l.returned_at is null
  left join public.profiles p on p.id = l.user_id
  where c.barcode = trim(p_barcode);

  if result is null then
    return jsonb_build_object(
      'found', false,
      'barcode', trim(p_barcode),
      'message', 'Aucun exemplaire ne porte ce code-barres.'
    );
  end if;

  return result;
end;
$$;


-- ============================================================
-- 2. Emprunt
-- ============================================================
-- L'agent scanne le livre, puis la carte de l'usager (ou saisit son numéro).
-- Fonctionne aussi bien pour une réservation Click & Collect que pour un habitant
-- qui se présente au comptoir sans avoir rien réservé.

create or replace function public.scan_checkout(p_barcode text, p_subscriber_number text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_book public.books;
  v_user_id uuid;
  v_user_commune bigint;
  v_agent_commune bigint;
  v_scope text;
  v_duration integer;
  v_due timestamptz;
  v_reservation_id bigint;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_copy from public.book_copies where barcode = trim(p_barcode);
  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Code-barres inconnu.');
  end if;

  select * into v_book from public.books where id = v_copy.book_id;

  select id, commune_id into v_user_id, v_user_commune
  from public.profiles where subscriber_number = trim(p_subscriber_number);

  if v_user_id is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun usager ne porte ce numéro d''abonné.');
  end if;

  if v_copy.status = 'borrowed' then
    return jsonb_build_object('ok', false, 'message', 'Cet exemplaire est déjà emprunté.');
  end if;

  if v_copy.status in ('in_transit', 'processing', 'lost', 'withdrawn') then
    return jsonb_build_object('ok', false,
      'message', 'Cet exemplaire n''est pas empruntable pour le moment (' || v_copy.status || ').');
  end if;

  -- Réservation mise de côté : elle doit appartenir à l'usager qui se présente
  if v_copy.status = 'reserved' then
    select r.id into v_reservation_id
    from public.reservations r
    where r.book_id = v_copy.book_id
      and r.user_id = v_user_id
      and r.status in ('pret', 'preparation')
    order by r.created_at
    limit 1;

    if v_reservation_id is null then
      return jsonb_build_object('ok', false,
        'message', 'Cet exemplaire est mis de côté pour un autre usager.');
    end if;
  end if;

  -- Règle de prêt de la communauté de communes
  v_agent_commune := coalesce(public.agent_commune_id(), v_copy.current_commune_id);

  select co.lending_scope, co.loan_duration_days
  into v_scope, v_duration
  from public.communes cm
  join public.communities co on co.id = cm.community_id
  where cm.id = v_copy.current_commune_id;

  v_duration := coalesce(v_duration, 21);

  if v_scope = 'commune' and v_user_commune is distinct from v_copy.current_commune_id then
    return jsonb_build_object('ok', false,
      'message', 'Cet usager est inscrit dans une autre commune, et le contrat limite le prêt à la médiathèque de sa commune.');
  end if;

  v_due := now() + (v_duration || ' days')::interval;

  insert into public.loans (
    copy_id, user_id, reservation_id,
    borrowed_at_commune_id, due_at, borrowed_by_agent
  ) values (
    v_copy.id, v_user_id, v_reservation_id,
    v_copy.current_commune_id, v_due, auth.uid()
  );

  update public.book_copies set status = 'borrowed' where id = v_copy.id;

  -- La réservation Click & Collect est soldée par le passage au comptoir
  if v_reservation_id is not null then
    update public.reservations
      set status = 'recupere', return_due_at = v_due
      where id = v_reservation_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'title', v_book.title,
    'author', v_book.author,
    'due_at', v_due,
    'from_reservation', v_reservation_id is not null,
    'message', 'Emprunt enregistré, à rendre avant le ' || to_char(v_due, 'DD/MM/YYYY') || '.'
  );
end;
$$;


-- ============================================================
-- 3. Retour
-- ============================================================
-- Un seul scan suffit : la base retrouve le prêt en cours. Le livre peut être rendu
-- dans une autre médiathèque que celle qui l'a prêté, si le contrat de la communauté
-- l'autorise. Dans ce cas un transfert de retour est créé automatiquement pour que
-- l'exemplaire retrouve sa médiathèque propriétaire.

create or replace function public.scan_return(p_barcode text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_book public.books;
  v_loan public.loans;
  v_here bigint;
  v_returns_anywhere boolean;
  v_late boolean := false;
  v_transfer_created boolean := false;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_copy from public.book_copies where barcode = trim(p_barcode);
  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Code-barres inconnu.');
  end if;

  select * into v_book from public.books where id = v_copy.book_id;

  v_here := coalesce(public.agent_commune_id(), v_copy.current_commune_id);

  select co.returns_anywhere into v_returns_anywhere
  from public.communes cm
  join public.communities co on co.id = cm.community_id
  where cm.id = v_here;

  v_returns_anywhere := coalesce(v_returns_anywhere, true);

  if not v_returns_anywhere and v_here is distinct from v_copy.owner_commune_id then
    return jsonb_build_object('ok', false,
      'message', 'Ce livre appartient à une autre médiathèque, et le contrat impose de le rendre sur place.');
  end if;

  select * into v_loan from public.loans where copy_id = v_copy.id and returned_at is null;

  if v_loan.id is not null then
    v_late := now() > v_loan.due_at;

    update public.loans
      set returned_at = now(),
          returned_at_commune_id = v_here,
          returned_by_agent = auth.uid()
      where id = v_loan.id;

    -- La réservation d'origine bascule dans l'historique de l'usager
    if v_loan.reservation_id is not null then
      update public.reservations set status = 'expiree' where id = v_loan.reservation_id;
    end if;
  end if;

  update public.book_copies
    set status = 'available',
        current_commune_id = v_here
    where id = v_copy.id;

  -- L'exemplaire est loin de chez lui : on prévient sa médiathèque propriétaire
  if v_here is distinct from v_copy.owner_commune_id then
    insert into public.transfers (
      copy_id, from_commune_id, to_commune_id, status, requested_by, notes
    ) values (
      v_copy.id, v_here, v_copy.owner_commune_id, 'requested', auth.uid(),
      'Retour rendu dans une autre médiathèque'
    );
    v_transfer_created := true;
  end if;

  return jsonb_build_object(
    'ok', true,
    'title', v_book.title,
    'author', v_book.author,
    'had_loan', v_loan.id is not null,
    'was_late', v_late,
    'needs_transfer', v_transfer_created,
    'shelf_location', v_copy.shelf_location,
    'message', case
      when v_transfer_created then 'Retour enregistré. Ce livre appartient à une autre médiathèque, il est à renvoyer.'
      when v_loan.id is null then 'Aucun prêt en cours pour cet exemplaire, il est remis en rayon.'
      when v_late then 'Retour enregistré, avec du retard.'
      else 'Retour enregistré.'
    end
  );
end;
$$;


-- ============================================================
-- 4. Rangement en rayon
-- ============================================================
-- L'agent scanne un livre rendu et l'écran lui dit où le reposer.

create or replace function public.scan_shelving(p_barcode text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_book public.books;
  v_commune text;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_copy from public.book_copies where barcode = trim(p_barcode);
  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Code-barres inconnu.');
  end if;

  select * into v_book from public.books where id = v_copy.book_id;
  select name into v_commune from public.communes where id = v_copy.owner_commune_id;

  if v_copy.status = 'borrowed' then
    return jsonb_build_object('ok', false,
      'title', v_book.title,
      'message', 'Ce livre est encore marqué comme emprunté, il faut d''abord enregistrer son retour.');
  end if;

  if v_copy.owner_commune_id is distinct from coalesce(public.agent_commune_id(), v_copy.owner_commune_id) then
    return jsonb_build_object('ok', true,
      'title', v_book.title,
      'author', v_book.author,
      'shelf_location', null,
      'message', 'Ce livre appartient à ' || v_commune || ', il est à mettre dans le bac de transfert.');
  end if;

  if v_copy.shelf_location is null or v_copy.shelf_location = '' then
    return jsonb_build_object('ok', true,
      'title', v_book.title,
      'author', v_book.author,
      'shelf_location', null,
      'needs_shelf', true,
      'message', 'Aucune cote enregistrée pour cet exemplaire, à renseigner.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'title', v_book.title,
    'author', v_book.author,
    'shelf_location', v_copy.shelf_location,
    'message', 'À ranger en ' || v_copy.shelf_location || '.'
  );
end;
$$;


-- ============================================================
-- 5. Transferts entre médiathèques
-- ============================================================

-- Départ : l'agent scanne le livre au moment de le mettre dans la caisse de transport.
create or replace function public.transfer_send(p_barcode text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_transfer public.transfers;
  v_dest text;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_copy from public.book_copies where barcode = trim(p_barcode);
  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Code-barres inconnu.');
  end if;

  select * into v_transfer
  from public.transfers
  where copy_id = v_copy.id and status = 'requested'
  order by requested_at
  limit 1;

  if v_transfer.id is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun transfert demandé pour ce livre.');
  end if;

  update public.transfers
    set status = 'in_transit', sent_at = now(), sent_by = auth.uid()
    where id = v_transfer.id;

  update public.book_copies set status = 'in_transit' where id = v_copy.id;

  select name into v_dest from public.communes where id = v_transfer.to_commune_id;

  return jsonb_build_object('ok', true, 'destination', v_dest,
    'message', 'Départ enregistré, en route vers ' || v_dest || '.');
end;
$$;

-- Arrivée : l'agent scanne le livre en ouvrant la caisse.
create or replace function public.transfer_receive(p_barcode text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_transfer public.transfers;
  v_book public.books;
  v_has_reservation boolean := false;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_copy from public.book_copies where barcode = trim(p_barcode);
  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Code-barres inconnu.');
  end if;

  select * into v_book from public.books where id = v_copy.book_id;

  select * into v_transfer
  from public.transfers
  where copy_id = v_copy.id and status = 'in_transit'
  order by sent_at
  limit 1;

  if v_transfer.id is null then
    return jsonb_build_object('ok', false, 'message', 'Ce livre n''était pas annoncé en transfert.');
  end if;

  update public.transfers
    set status = 'received', received_at = now(), received_by = auth.uid()
    where id = v_transfer.id;

  v_has_reservation := v_transfer.reservation_id is not null;

  update public.book_copies
    set current_commune_id = v_transfer.to_commune_id,
        status = case when v_has_reservation then 'reserved' else 'available' end
    where id = v_copy.id;

  -- Le livre était attendu par un usager : sa réservation passe à « prêt à récupérer »
  if v_has_reservation then
    update public.reservations set status = 'pret' where id = v_transfer.reservation_id;

    insert into public.notifications (user_id, message)
    select r.user_id, 'Ton livre « ' || v_book.title || ' » est arrivé, tu peux venir le récupérer.'
    from public.reservations r where r.id = v_transfer.reservation_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'title', v_book.title,
    'author', v_book.author,
    'for_reservation', v_has_reservation,
    'shelf_location', v_copy.shelf_location,
    'message', case
      when v_has_reservation then 'Arrivée enregistrée. À mettre de côté, un usager l''attend.'
      else 'Arrivée enregistrée, à ranger en rayon.'
    end
  );
end;
$$;
