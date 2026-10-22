-- Comptoir : prêt qui tient compte des commandes de l'appli (22/10/2026)
-- ============================================================
-- Une commande (en préparation ou prête) ne bloque pas l'exemplaire en rayon :
-- il reste « disponible ». Au comptoir, scan_checkout pouvait donc :
--   - prêter à quelqu'un d'autre un livre commandé dans l'appli ;
--   - prêter à l'usager le livre qu'il a commandé sans clôturer sa commande
--     (qui finissait « expirée » alors que le livre était chez lui).
-- counter_checkout vérifie d'abord les commandes, appelle scan_checkout (inchangé)
-- puis rattache le prêt à la commande de l'usager s'il en a une.

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

revoke all on function public.counter_checkout(text, text) from public, anon;
grant execute on function public.counter_checkout(text, text) to authenticated;

-- Vérification : doit renvoyer counter_checkout.
select proname from pg_proc where proname = 'counter_checkout';
