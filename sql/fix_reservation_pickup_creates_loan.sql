-- Corrige « Marquer récupéré » qui ne créait jamais de vrai prêt (22/09/2026)
-- ============================================================
-- Depuis le passage aux exemplaires/prêts du 13/09/2026 (voir
-- sql/add_copies_communities_loans.sql), deux mécanismes coexistaient sans
-- jamais avoir été reliés :
--   1. L'ancien : reservations.status → 'recupere' + un trigger qui fixe
--      juste reservations.return_due_at à +21 jours (voir
--      fix_reservation_deadlines_and_returns.sql). C'est tout ce que fait le
--      bouton "Marquer récupéré" de l'onglet Réservations.
--   2. Le nouveau : la table loans, liée à un exemplaire précis
--      (book_copies), utilisée par scan_checkout/scan_return et par l'onglet
--      "Prêts en cours".
-- Résultat : un livre marqué "récupéré" depuis l'onglet Réservations
-- n'apparaissait jamais dans "Prêts en cours", et son exemplaire ne passait
-- jamais à 'borrowed' (RLS/statut jamais mis à jour, aucune date de retour
-- réelle suivie côté exemplaire).

create or replace function public.mark_reservation_picked_up(p_reservation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
$$;
