-- BliGO — Tournées de transfert + demande automatique au moment de préparer
-- une réservation (23/09/2026)
-- ============================================================
-- Deux manques identifiés avec Mégane pour un réseau à plusieurs
-- médiathèques (ex. Espace Sud, 12 bibliothèques, 3 tournées/semaine) :
--
-- 1. Aujourd'hui, rien ne déclenche de transfert quand une réservation ne
--    peut être honorée que par un exemplaire d'une AUTRE médiathèque du
--    réseau — seul un retour mal aiguillé (scan_return/scan_checkout) en
--    créait un. "Marquer prêt" sur une réservation ne vérifiait même pas la
--    disponibilité, il changeait juste le statut en confiance.
-- 2. Aucun jour de tournée n'est rattaché à une médiathèque, impossible de
--    regrouper les envois par tournée dans l'écran Transferts.

-- 1) Jour de tournée, fixe par médiathèque (réglé par communauté de communes,
--    donc depuis l'espace super admin — superadmin.html).
alter table public.communes add column if not exists transfer_day text;
comment on column public.communes.transfer_day is 'Jour de la tournée de transferts de cette médiathèque (texte libre, ex. "Lundi") — fixé par la communauté de communes. Null = pas encore assignée à une tournée.';

-- 2) Préparer une réservation vérifie maintenant la disponibilité :
--    - un exemplaire est déjà dans la médiathèque de l'usager → prête direct.
--    - un exemplaire n'existe qu'ailleurs dans le réseau → demande un
--      transfert (visible dans Transferts) au lieu de mentir sur le statut.
--    - aucun exemplaire nulle part → message clair, rien ne change.
create or replace function public.prepare_reservation(p_reservation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reservation public.reservations;
  v_user_commune bigint;
  v_copy public.book_copies;
  v_here bigint;
  v_dest_name text;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_reservation from public.reservations where id = p_reservation_id;
  if v_reservation.id is null then
    return jsonb_build_object('ok', false, 'message', 'Réservation introuvable.');
  end if;
  if v_reservation.status <> 'preparation' then
    return jsonb_build_object('ok', false, 'message', 'Cette réservation n''est plus en préparation.');
  end if;

  select commune_id into v_user_commune from public.profiles where id = v_reservation.user_id;
  v_here := coalesce(v_user_commune, public.agent_commune_id());

  -- Priorité à un exemplaire déjà disponible dans la médiathèque de l'usager.
  select c.* into v_copy
  from public.book_copies c
  where c.book_id = v_reservation.book_id and c.status = 'available'
  order by (c.current_commune_id = v_here) desc, c.id
  limit 1;

  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun exemplaire disponible pour ce livre en ce moment, dans aucune médiathèque du réseau.');
  end if;

  if v_copy.current_commune_id = v_here then
    update public.reservations set status = 'pret' where id = p_reservation_id;
    return jsonb_build_object('ok', true, 'needs_transfer', false, 'message', 'Réservation prête à récupérer.');
  end if;

  -- L'exemplaire disponible est ailleurs dans le réseau : on le réserve tout
  -- de suite pour cet usager (personne d'autre ne doit le prendre) et on
  -- demande le transfert — transfer_receive() passera la réservation à
  -- « prêt » automatiquement à l'arrivée du livre (voir add_scan_operations.sql).
  update public.book_copies set status = 'reserved' where id = v_copy.id;

  insert into public.transfers (copy_id, from_commune_id, to_commune_id, status, requested_by, reservation_id, notes)
  values (v_copy.id, v_copy.current_commune_id, v_here, 'requested', auth.uid(), p_reservation_id, 'Demandé pour une réservation en préparation');

  select name into v_dest_name from public.communes where id = v_copy.current_commune_id;

  return jsonb_build_object(
    'ok', true,
    'needs_transfer', true,
    'message', 'Aucun exemplaire ici : transfert demandé depuis ' || coalesce(v_dest_name, 'une autre médiathèque') || '. L''usager sera prévenu à l''arrivée.'
  );
end;
$$;
