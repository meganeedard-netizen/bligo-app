-- BliGO, 26/11/2026 : prêt de matériel (liseuses, tablettes, casques…), demande de Mégane.
-- Même principe que les instruments : quantité et durée à part, accessoires,
-- fiche à signer, prêt au Comptoir uniquement (pas à l'automate). En plus :
-- caution affichée, âge minimum, liste à vérifier au retour.
alter table public.communes add column if not exists max_loans_materiel integer not null default 1;
alter table public.communes add column if not exists materiel_loan_duration_days integer not null default 21;
alter table public.communes add column if not exists materiel_deposit_cents integer;
alter table public.communes add column if not exists materiel_min_age integer not null default 0;
alter table public.communes add column if not exists materiel_return_checklist text not null default E'Appareil chargé\nCompte de l''usager déconnecté\nContenu personnel effacé\nChargeur et câble rendus';
alter table public.communes add column if not exists materiel_charter text;

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

  -- Matériel (liseuses, tablettes…, 26/11/2026) : compté à part, comme les instruments.
  if v_category = 'Matériel' then
    select c.* into v_commune from public.communes c join public.profiles p on p.commune_id = c.id where p.id = p_user_id;
    v_max := coalesce(v_commune.max_loans_materiel, 1);
    select
      (select count(*) from public.reservations r join public.books b on b.id = r.book_id
        where r.user_id = p_user_id and r.status in ('panier', 'preparation', 'pret') and b.category = 'Matériel')
      + (select count(*) from public.loans l join public.book_copies c on c.id = l.copy_id join public.books b on b.id = c.book_id
          where l.user_id = p_user_id and l.returned_at is null and b.category = 'Matériel')
    into v_count;
    if v_count >= v_max + v_extra then
      return format('Limite atteinte : %s appareil%s maximum à la fois.', v_max, case when v_max > 1 then 's' else '' end);
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
        and coalesce(b.category = 'Jeunesse', false) = v_is_jeunesse and coalesce(b.category, '') not in ('Instruments', 'Matériel'))
    + (select count(*) from public.loans l join public.book_copies c on c.id = l.copy_id join public.books b on b.id = c.book_id
        where l.user_id = p_user_id and l.returned_at is null
          and coalesce(b.category = 'Jeunesse', false) = v_is_jeunesse and coalesce(b.category, '') not in ('Instruments', 'Matériel'))
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
    case when (select category from public.books where id = p_book_id) = 'Matériel'
      then (select materiel_loan_duration_days from public.communes where id = p_commune_id)
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
      where l.user_id = p_user_id and l.returned_at is null and coalesce(b.category, '') not in ('Instruments', 'Matériel'))
    + (select count(*) from public.reservations r join public.books b on b.id = r.book_id
      where r.user_id = p_user_id and coalesce(b.category, '') not in ('Instruments', 'Matériel') and r.status in ('panier', 'preparation', 'pret'))
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

  if v_user_tariff_category = 'famille' and coalesce(v_book.category, '') not in ('Instruments', 'Matériel') and public.family_quota_reached(v_user_id) then
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
  if exists (select 1 from public.books where id = v_reservation.book_id and category in ('Instruments', 'Matériel')) then
    return jsonb_build_object('ok', false, 'message', 'Instrument ou matériel : prête-le au Comptoir en le scannant, pour remettre ses accessoires et imprimer la fiche de prêt.');
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
$function$
;
CREATE OR REPLACE FUNCTION public.age_block_message(p_user uuid, p_book bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_min integer; v_category text; v_commune bigint; v_rating text; v_year integer; v_tariff text; v_age integer; v_declared integer; v_on date;
begin
  select coalesce(min_age, case when adult_only then 18 end), age_rating into v_min, v_rating from public.books where id = p_book;
  -- Matériel : âge minimum choisi par la médiathèque (Réglages).
  select category, commune_id into v_category, v_commune from public.books where id = p_book;
  if v_category = 'Matériel' then
    v_min := greatest(coalesce(v_min, 0), coalesce((select materiel_min_age from public.communes where id = v_commune), 0));
  end if;
  if coalesce(v_min, 0) = 0 then return null; end if;
  select birth_year, tariff_category, declared_age, declared_on into v_year, v_tariff, v_declared, v_on from public.profiles where id = p_user;
  v_age := public.reader_min_age(v_year, v_tariff);
  -- L'année saisie par la médiathèque l'emporte sur l'âge déclaré.
  if v_age is null and v_tariff = 'mineur' and v_declared is not null then
    v_age := v_declared + extract(year from age(current_date, v_on))::int;
  end if;
  if (v_age is not null and v_age < v_min) or (v_age is null and v_tariff = 'mineur' and v_min >= 16) then
    if v_category = 'Matériel' then
      return 'Ce matériel est prêté à partir de ' || v_min || ' ans.';
    end if;
    return 'Ce document est réservé aux ' || v_min || ' ans et plus' || coalesce(' (' || v_rating || ')', '') || '.';
  end if;
  return null;
end $function$
;

create or replace function public.update_commune_materiel(p_commune_id bigint, p_max integer, p_days integer, p_deposit_cents integer, p_min_age integer, p_checklist text, p_charter text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;
  update public.communes set max_loans_materiel = greatest(0, coalesce(p_max, 1)),
    materiel_loan_duration_days = greatest(1, coalesce(p_days, 21)),
    materiel_deposit_cents = nullif(greatest(0, coalesce(p_deposit_cents, 0)), 0),
    materiel_min_age = least(18, greatest(0, coalesce(p_min_age, 0))),
    materiel_return_checklist = coalesce(trim(p_checklist), ''),
    materiel_charter = nullif(trim(coalesce(p_charter, '')), '')
  where id = p_commune_id;
end $$;
revoke all on function public.update_commune_materiel(bigint, integer, integer, integer, integer, text, text) from public, anon;
grant execute on function public.update_commune_materiel(bigint, integer, integer, integer, integer, text, text) to authenticated;
