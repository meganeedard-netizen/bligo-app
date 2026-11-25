-- BliGO, 25/11/2026 : prêt d'instruments de musique (demande du Tampon).
-- Catégorie à part : leur propre quantité et leur propre durée, sans toucher aux
-- limites des livres. Accessoires listés sur la fiche, contrôlés au retour.
alter table public.books add column if not exists accessories text;
alter table public.book_copies add column if not exists missing_accessories text;
alter table public.communes add column if not exists max_loans_instruments integer not null default 1;
alter table public.communes add column if not exists instrument_loan_duration_days integer not null default 28;
alter table public.communes add column if not exists instrument_charter text;
alter table public.books drop constraint if exists books_category_check;


alter table public.books add constraint books_category_check CHECK (((category IS NULL) OR (category = ANY (ARRAY['Fonds local'::text, 'Roman'::text, 'Thriller'::text, 'Fantasy'::text, 'Jeunesse'::text, 'BD'::text, 'Poésie & théâtre'::text, 'Documentaire'::text, 'Sciences & nature'::text, 'Voyages'::text, 'Sports & loisirs'::text, 'Bien-être'::text, 'Maison'::text, 'Histoire'::text, 'Culture'::text, 'Jeux'::text, 'Instruments'::text, 'Autres'::text]))));

insert into public.document_types (commune_id, label, kind, sort_order)
select null, 'Instrument de musique', 'autre', 110
where not exists (select 1 from public.document_types where commune_id is null and lower(label) = 'instrument de musique');

CREATE OR REPLACE FUNCTION public.loan_limit_error(p_user_id uuid, p_book_id bigint, p_already_counted boolean DEFAULT false)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- Instruments de musique (25/11/2026) : comptés à part des autres documents.
  if v_category = 'Instruments' then
    select c.* into v_commune from public.communes c join public.profiles p on p.commune_id = c.id where p.id = p_user_id;
    v_max := coalesce(v_commune.max_loans_instruments, 1);
    select
      (select count(*) from public.reservations r join public.books b on b.id = r.book_id
        where r.user_id = p_user_id and r.status in ('panier', 'preparation', 'pret') and b.category = 'Instruments')
      + (select count(*) from public.loans l join public.book_copies c on c.id = l.copy_id join public.books b on b.id = c.book_id
          where l.user_id = p_user_id and l.returned_at is null and b.category = 'Instruments')
    into v_count;
    if v_count >= v_max + v_extra then
      return format('Limite atteinte : %s instrument%s maximum à la fois.', v_max, case when v_max > 1 then 's' else '' end);
    end if;
    return null;
  end if;

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
        and coalesce(b.category = 'Jeunesse', false) = v_is_jeunesse and b.category is distinct from 'Instruments')
    + (select count(*) from public.loans l join public.book_copies c on c.id = l.copy_id join public.books b on b.id = c.book_id
        where l.user_id = p_user_id and l.returned_at is null
          and coalesce(b.category = 'Jeunesse', false) = v_is_jeunesse and b.category is distinct from 'Instruments')
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
$function$
;

CREATE OR REPLACE FUNCTION public.effective_loan_duration_days(p_book_id bigint, p_commune_id bigint)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select loan_duration_days_override from public.books where id = p_book_id),
    case when (select category from public.books where id = p_book_id) = 'Instruments'
      then (select instrument_loan_duration_days from public.communes where id = p_commune_id)
    end,
    case when (select is_new_release from public.books where id = p_book_id)
      then (select new_release_loan_duration_days from public.communes where id = p_commune_id)
    end,
    (select loan_duration_days from public.communes where id = p_commune_id),
    (select co.loan_duration_days
       from public.communes cm join public.communities co on co.id = cm.community_id
       where cm.id = p_commune_id),
    21
  );
$function$
;

CREATE OR REPLACE FUNCTION public.family_quota_reached(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    (select count(*) from public.loans l join public.book_copies bc on bc.id = l.copy_id join public.books b on b.id = bc.book_id
      where l.user_id = p_user_id and l.returned_at is null and b.category is distinct from 'Instruments')
    + (select count(*) from public.reservations r join public.books b on b.id = r.book_id
      where r.user_id = p_user_id and b.category is distinct from 'Instruments' and r.status in ('panier', 'preparation', 'pret'))
    >= (select coalesce(c.family_max_general, 10) + coalesce(c.family_max_jeunesse, 10)
          from public.profiles p join public.communes c on c.id = p.commune_id where p.id = p_user_id);
$function$
;

CREATE OR REPLACE FUNCTION public.scan_checkout(p_barcode text, p_subscriber_number text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_copy public.book_copies;
  v_book public.books;
  v_user_id uuid;
  v_user_commune bigint;
  v_user_flagged boolean;
  v_user_tariff_category text;
  v_reservation_id bigint;
  v_membership text;
  v_duration integer;
  v_due timestamptz;
  v_agent_commune bigint;
  v_restricted_categories text[];
  v_blocks_new_release boolean;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_copy from public.book_copies where barcode = public.resolve_copy_code(p_barcode, 'checkout');
  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Code-barres inconnu.');
  end if;

  select * into v_book from public.books where id = v_copy.book_id;

  select id, commune_id, coalesce(flagged, false), tariff_category
  into v_user_id, v_user_commune, v_user_flagged, v_user_tariff_category
  from public.profiles where subscriber_number = trim(p_subscriber_number);

  if v_user_id is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun usager ne porte ce numéro d''abonné.');
  end if;

  if v_user_tariff_category = 'mineur' and coalesce(v_book.adult_only, false) then
    return jsonb_build_object('ok', false, 'message', 'Ce livre est réservé aux comptes majeurs.');
  end if;

  if public.age_block_message(v_user_id, v_book.id) is not null then
    return jsonb_build_object('ok', false, 'message', public.age_block_message(v_user_id, v_book.id));
  end if;

  if v_copy.status = 'borrowed' then
    return jsonb_build_object('ok', false, 'message', 'Cet exemplaire est déjà emprunté.');
  end if;

  if v_copy.status in ('in_transit', 'processing', 'lost', 'withdrawn') then
    return jsonb_build_object('ok', false,
      'message', 'Cet exemplaire n''est pas empruntable pour le moment (' || v_copy.status || ').');
  end if;

  select coalesce(flagged_restricted_categories, '{}'), coalesce(flagged_blocks_new_releases, true)
  into v_restricted_categories, v_blocks_new_release
  from public.communes where id = v_user_commune;

  if v_user_flagged and v_book.category = any(coalesce(v_restricted_categories, '{}')) then
    return jsonb_build_object('ok', false,
      'message', 'Cet usager est actuellement restreint et ne peut pas emprunter dans la catégorie « ' || v_book.category || ' ».');
  end if;

  if v_user_flagged and coalesce(v_blocks_new_release, true) and coalesce(v_book.is_new_release, false) then
    return jsonb_build_object('ok', false, 'message', 'Cet usager est actuellement restreint et ne peut pas emprunter les nouveautés.');
  end if;

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

  v_agent_commune := coalesce(public.agent_commune_id(), v_copy.current_commune_id);

  if public.has_open_debt(v_user_id) then
    return jsonb_build_object('ok', false, 'message', 'Cet usager a un document perdu ou abîmé non réglé : voir sa fiche avant tout nouvel emprunt.');
  end if;

  v_membership := public.membership_status(v_user_id, v_copy.current_commune_id);
  if v_membership <> 'ok' then
    return jsonb_build_object('ok', false, 'message', public.membership_error_message(v_membership));
  end if;

  if v_user_tariff_category = 'famille' and v_book.category is distinct from 'Instruments' and public.family_quota_reached(v_user_id) then
    return jsonb_build_object('ok', false, 'message', 'Le quota de la carte famille est atteint : un document doit être rendu avant un nouvel emprunt.');
  end if;

  v_duration := public.effective_loan_duration_days(v_book.id, v_copy.current_commune_id);
  v_due := now() + (v_duration || ' days')::interval;

  insert into public.loans (
    copy_id, user_id, reservation_id,
    borrowed_at_commune_id, due_at, borrowed_by_agent
  ) values (
    v_copy.id, v_user_id, v_reservation_id,
    v_copy.current_commune_id, v_due, auth.uid()
  );

  update public.book_copies set status = 'borrowed' where id = v_copy.id;

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
$function$
;

CREATE OR REPLACE FUNCTION public.scan_lookup(p_barcode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    'category', b.category,
    'accessories', b.accessories,
    'missing_accessories', c.missing_accessories,
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
  where c.barcode = public.resolve_copy_code(p_barcode, 'lookup');

  if result is null then
    return jsonb_build_object(
      'found', false,
      'barcode', trim(p_barcode),
      'message', 'Aucun exemplaire ne porte ce code-barres.'
    );
  end if;

  return result;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.sip_item_info(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_c public.book_copies;
  v_b public.books;
  v_l public.loans;
  v_card text;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_c from public.book_copies where barcode = public.resolve_copy_code(p_code, 'return');
  if v_c.id is null then
    return jsonb_build_object('found', false);
  end if;
  select * into v_b from public.books where id = v_c.book_id;
  select * into v_l from public.loans where copy_id = v_c.id and returned_at is null order by id desc limit 1;
  if v_l.id is not null then
    select subscriber_number into v_card from public.profiles where id = v_l.user_id;
  end if;

  return jsonb_build_object(
    'found', true,
    'barcode', v_c.barcode,
    'status', v_c.status,
    'title', v_b.title,
    'author', v_b.author,
    'format', v_b.format,
    'category', v_b.category,
    'owner', (select name from public.communes where id = v_c.owner_commune_id),
    'location', (select name from public.communes where id = v_c.current_commune_id),
    'shelf', v_c.shelf_location,
    'loan_id', v_l.id,
    'due_at', v_l.due_at,
    'borrower_card', v_card,
    'holds_waiting', (select count(*) from public.holds where book_id = v_b.id and status = 'waiting')
  );
end;
$function$
;


-- Accessoires manquants, notés au retour (vide = tout est là).
create or replace function public.set_missing_accessories(p_barcode text, p_missing text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_agent() or public.is_super_admin()) then raise exception 'Accès réservé aux agents'; end if;
  update public.book_copies set missing_accessories = nullif(trim(coalesce(p_missing, '')), '')
   where barcode = public.resolve_copy_code(p_barcode, 'lookup')
     and (public.is_super_admin() or public.agent_commune_id() in (current_commune_id, owner_commune_id));
  if not found then raise exception 'Exemplaire introuvable dans ta médiathèque.'; end if;
end $$;
revoke all on function public.set_missing_accessories(text, text) from public, anon;
grant execute on function public.set_missing_accessories(text, text) to authenticated;

create or replace function public.update_commune_instruments(p_commune_id bigint, p_max integer, p_days integer, p_charter text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;
  update public.communes set max_loans_instruments = greatest(0, coalesce(p_max, 1)),
    instrument_loan_duration_days = greatest(1, coalesce(p_days, 28)),
    instrument_charter = nullif(trim(coalesce(p_charter, '')), '')
  where id = p_commune_id;
end $$;
revoke all on function public.update_commune_instruments(bigint, integer, integer, text) from public, anon;
grant execute on function public.update_commune_instruments(bigint, integer, integer, text) to authenticated;

CREATE OR REPLACE FUNCTION public.mark_reservation_picked_up(p_reservation_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_reservation public.reservations;
  v_copy public.book_copies;
  v_here bigint;
  v_duration integer;
  v_due timestamptz;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_reservation from public.reservations where id = p_reservation_id;
  if v_reservation.id is null then
    return jsonb_build_object('ok', false, 'message', 'Réservation introuvable.');
  end if;
  if v_reservation.status = 'recupere' then
    return jsonb_build_object('ok', false, 'message', 'Cette réservation a déjà été marquée récupérée.');
  end if;

  -- Instrument : accessoires à vérifier et fiche à signer, donc prêt au Comptoir.
  if exists (select 1 from public.books where id = v_reservation.book_id and category = 'Instruments') then
    return jsonb_build_object('ok', false, 'message', 'Instrument : prête-le au Comptoir en le scannant, pour remettre ses accessoires et imprimer la fiche de prêt.');
  end if;

  v_here := public.agent_commune_id();

  -- Un exemplaire déjà mis de côté pour cette réservation (arrivé par
  -- transfert) est prioritaire ; sinon n'importe quel exemplaire disponible,
  -- de préférence dans la médiathèque de l'agent qui valide le retrait.
  select c.* into v_copy
  from public.book_copies c
  where c.book_id = v_reservation.book_id
    and c.status in ('reserved', 'available')
  order by (c.status = 'reserved') desc, (c.current_commune_id = v_here) desc, c.id
  limit 1;

  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun exemplaire disponible pour ce livre en ce moment.');
  end if;

  v_duration := public.effective_loan_duration_days(v_reservation.book_id, v_copy.current_commune_id);
  v_due := now() + (v_duration || ' days')::interval;

  insert into public.loans (
    copy_id, user_id, reservation_id, borrowed_at_commune_id, due_at, borrowed_by_agent
  ) values (
    v_copy.id, v_reservation.user_id, v_reservation.id, v_copy.current_commune_id, v_due, auth.uid()
  );

  update public.book_copies set status = 'borrowed' where id = v_copy.id;

  -- Déclenche notify_on_ready() (notification usager + return_due_at, gardé
  -- tel quel pour ne rien casser côté affichage usager existant).
  update public.reservations set status = 'recupere' where id = p_reservation_id;

  return jsonb_build_object(
    'ok', true,
    'due_at', v_due,
    'message', 'Prêt enregistré, à rendre avant le ' || to_char(v_due, 'DD/MM/YYYY') || '.'
  );
end;
$function$;
