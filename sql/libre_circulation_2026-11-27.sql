-- Libre circulation des documents dans un réseau (27/11/2026, demande de Mégane).
alter table public.communities add column if not exists floating_collection boolean not null default false;
comment on column public.communities.floating_collection is 'Libre circulation : un document rendu dans une autre médiathèque du réseau y reste (pas de transfert retour).';
CREATE OR REPLACE FUNCTION public.scan_return(p_barcode text, p_condition text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_copy public.book_copies;
  v_book public.books;
  v_loan public.loans;
  v_here bigint;
  v_returns_anywhere boolean;
  v_late boolean := false;
  v_transfer_created boolean := false;
  v_late_fee_cents integer := 0;
  v_user_commune bigint;
  v_grace_days integer;
  v_days_late integer;
  v_should_flag boolean := false;
  v_owner_bdp boolean;
  v_depot public.depots;
  v_bdp_recall boolean := false;
  v_kept_in_depot boolean := false;
  v_floating boolean := false;
  v_kept_floating boolean := false;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  if p_condition is not null and p_condition not in ('bon', 'mauvais') then
    raise exception 'État de retour invalide : % (attendu bon ou mauvais)', p_condition;
  end if;

  select * into v_copy from public.book_copies where barcode = public.resolve_copy_code(p_barcode, 'return');
  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Code-barres inconnu.');
  end if;
  select * into v_book from public.books where id = v_copy.book_id;

  v_here := coalesce(public.agent_commune_id(), v_copy.current_commune_id);
  select is_bdp into v_owner_bdp from public.communes where id = v_copy.owner_commune_id;
  v_owner_bdp := coalesce(v_owner_bdp, false);

  select co.returns_anywhere into v_returns_anywhere
    from public.communes cm join public.communities co on co.id = cm.community_id where cm.id = v_here;
  v_returns_anywhere := coalesce(v_returns_anywhere, true);
  -- Libre circulation (27/11/2026, réseaux type Pass'Média, Le Tampon) : le
  -- document rendu dans une autre médiathèque du MÊME réseau y reste, sans
  -- transfert vers sa médiathèque d'origine.
  select coalesce(co.floating_collection, false) into v_floating
    from public.communes h join public.communes o on o.id = v_copy.owner_commune_id
    join public.communities co on co.id = h.community_id
   where h.id = v_here and h.community_id = o.community_id;
  v_floating := coalesce(v_floating, false);

  if not v_owner_bdp and not v_returns_anywhere and v_here is distinct from v_copy.owner_commune_id then
    return jsonb_build_object('ok', false,
      'message', 'Ce livre appartient à une autre médiathèque, et le contrat impose de le rendre sur place.');
  end if;

  select * into v_loan from public.loans where copy_id = v_copy.id and returned_at is null;
  if v_loan.id is not null then
    v_late := now() > v_loan.due_at;
    select commune_id into v_user_commune from public.profiles where id = v_loan.user_id;
    select coalesce(late_fee_grace_days, 7) into v_grace_days from public.communes where id = v_user_commune;
    v_grace_days := coalesce(v_grace_days, 7);
    v_days_late := greatest(0, extract(day from (now() - v_loan.due_at))::int);
    v_late_fee_cents := public.calculate_late_fee_cents(v_loan.due_at, now(), v_user_commune);
    v_should_flag := (p_condition = 'mauvais') or (v_days_late > v_grace_days);

    update public.loans set returned_at = now(), returned_at_commune_id = v_here, returned_by_agent = auth.uid()
     where id = v_loan.id;

    if v_should_flag then
      perform public.set_user_flagged(v_loan.user_id, true,
        case
          when p_condition = 'mauvais' and v_days_late > v_grace_days then 'Livre rendu abîmé et en retard'
          when p_condition = 'mauvais' then 'Livre rendu abîmé'
          else 'Retard de plus de ' || v_grace_days || ' jours'
        end);
    end if;
    if v_loan.reservation_id is not null then
      update public.reservations set status = 'expiree' where id = v_loan.reservation_id;
    end if;
  end if;

  update public.book_copies
     set status = 'available', current_commune_id = v_here, condition = coalesce(p_condition, condition)
   where id = v_copy.id;

  if v_owner_bdp then
    if v_here = v_copy.owner_commune_id then
      update public.depots set ended_at = now() where copy_id = v_copy.id and ended_at is null;
    else
      select * into v_depot from public.depots where copy_id = v_copy.id and ended_at is null;
      if v_depot.id is null or v_depot.library_commune_id <> v_here then
        -- Rendu dans une autre bibliothèque du réseau : le dépôt suit le document
        -- (un rappel en cours est conservé).
        perform public._open_depot(v_copy.id, v_here);
        if v_depot.id is not null and v_depot.recall_requested_at is not null then
          update public.depots
             set recall_requested_at = v_depot.recall_requested_at, recall_requested_by = v_depot.recall_requested_by,
                 recall_for_commune_id = v_depot.recall_for_commune_id, recall_reservation_id = v_depot.recall_reservation_id,
                 recall_reason = v_depot.recall_reason
           where copy_id = v_copy.id and ended_at is null;
        end if;
        select * into v_depot from public.depots where copy_id = v_copy.id and ended_at is null;
      end if;
      if v_depot.recall_requested_at is not null then
        v_bdp_recall := true;
        v_transfer_created := public._request_transfer(v_copy.id, v_here, v_copy.owner_commune_id, 'depot_retour', null,
          'Retour demandé par la bibliothèque départementale');
        v_transfer_created := true;
      else
        v_kept_in_depot := true;
      end if;
    end if;
  elsif v_here is distinct from v_copy.owner_commune_id and v_floating then
    v_kept_floating := true;
  elsif v_here is distinct from v_copy.owner_commune_id then
    v_transfer_created := public._request_transfer(v_copy.id, v_here, v_copy.owner_commune_id, 'standard', null,
      'Retour rendu dans une autre médiathèque');
    v_transfer_created := true;
  end if;

  return jsonb_build_object(
    'ok', true, 'title', v_book.title, 'author', v_book.author,
    'had_loan', v_loan.id is not null, 'was_late', v_late, 'late_fee_cents', v_late_fee_cents,
    'user_flagged', v_should_flag, 'needs_transfer', v_transfer_created,
    'depot_bdp', v_owner_bdp, 'bdp_recall', v_bdp_recall,
    'shelf_location', v_copy.shelf_location,
    'message', case
      when v_bdp_recall then 'Retour enregistré. La bibliothèque départementale a demandé ce document : à renvoyer avec la prochaine navette.'
      when v_transfer_created then 'Retour enregistré. Ce livre appartient à une autre médiathèque, il est à renvoyer.'
      when v_late_fee_cents > 0 then 'Retour enregistré, avec retard : ' || to_char(v_late_fee_cents / 100.0, 'FM999990.00') || ' € de pénalité.'
      when v_late then 'Retour enregistré, avec du retard (dans la franchise, aucune pénalité).'
      when v_loan.id is null then 'Aucun prêt en cours pour cet exemplaire, il est remis en rayon.'
      when v_kept_floating then 'Retour enregistré. Ce document circule librement dans le réseau : il reste ici, à remettre en rayon.'
      when v_kept_in_depot then 'Retour enregistré. Document de la bibliothèque départementale en dépôt ici : à remettre en rayon.'
      else 'Retour enregistré.'
    end);
end;
$function$
;
