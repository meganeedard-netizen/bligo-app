-- BliGO, 27/11/2026 : suivi de la caution du matériel (demande de Mégane).
-- Notée sur le prêt : versée au comptoir, puis rendue ou gardée au retour.
alter table public.loans add column if not exists deposit_cents integer;
alter table public.loans add column if not exists deposit_method text;
alter table public.loans add column if not exists deposit_status text;
alter table public.loans add column if not exists deposit_at timestamptz;
alter table public.loans add column if not exists deposit_settled_at timestamptz;
alter table public.loans add column if not exists deposit_note text;
alter table public.loans drop constraint if exists loans_deposit_status_check;
alter table public.loans add constraint loans_deposit_status_check check (deposit_status is null or deposit_status in ('versee', 'rendue', 'gardee'));

-- Caution reçue au comptoir, pour le prêt en cours de cet exemplaire.
create or replace function public.record_loan_deposit(p_barcode text, p_cents integer, p_method text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_loan public.loans;
begin
  if not (public.is_agent() or public.is_super_admin()) then raise exception 'Accès réservé aux agents'; end if;
  if coalesce(p_cents, 0) <= 0 then raise exception 'Montant de caution invalide'; end if;
  if p_method not in ('cheque', 'especes', 'carte', 'virement') then raise exception 'Moyen de paiement inconnu'; end if;
  select l.* into v_loan from public.loans l join public.book_copies c on c.id = l.copy_id
   where c.barcode = public.resolve_copy_code(p_barcode, 'lookup') and l.returned_at is null
   order by l.id desc limit 1;
  if v_loan.id is null then raise exception 'Aucun prêt en cours pour cet exemplaire.'; end if;
  if not public.agent_sees_commune(v_loan.borrowed_at_commune_id) then raise exception 'Prêt d''une autre médiathèque.'; end if;
  update public.loans set deposit_cents = p_cents, deposit_method = p_method, deposit_status = 'versee', deposit_at = now(),
    deposit_settled_at = null, deposit_note = null where id = v_loan.id;
  return jsonb_build_object('ok', true, 'loan_id', v_loan.id);
end $$;
revoke all on function public.record_loan_deposit(text, integer, text) from public, anon;
grant execute on function public.record_loan_deposit(text, integer, text) to authenticated;

-- Caution rendue à l'usager, ou gardée (casse, manque…).
create or replace function public.settle_loan_deposit(p_loan_id bigint, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_loan public.loans;
begin
  if not (public.is_agent() or public.is_super_admin()) then raise exception 'Accès réservé aux agents'; end if;
  if p_status not in ('rendue', 'gardee') then raise exception 'Statut inconnu'; end if;
  select * into v_loan from public.loans where id = p_loan_id;
  if v_loan.id is null or v_loan.deposit_status is null then raise exception 'Aucune caution sur ce prêt.'; end if;
  if not public.agent_sees_commune(v_loan.borrowed_at_commune_id) then raise exception 'Prêt d''une autre médiathèque.'; end if;
  update public.loans set deposit_status = p_status, deposit_settled_at = now(),
    deposit_note = nullif(trim(coalesce(p_note, '')), '') where id = p_loan_id;
end $$;
revoke all on function public.settle_loan_deposit(bigint, text, text) from public, anon;
grant execute on function public.settle_loan_deposit(bigint, text, text) to authenticated;

-- Cautions encore détenues par la médiathèque (réseau de l'agent).
create or replace function public.list_open_deposits()
returns table (loan_id bigint, payer text, card text, title text, amount_cents integer, method text, deposit_at timestamptz, due_at timestamptz, returned_at timestamptz)
language sql stable security definer set search_path = public as $$
  select l.id, p.full_name, p.subscriber_number, b.title, l.deposit_cents, l.deposit_method, l.deposit_at, l.due_at, l.returned_at
    from public.loans l
    join public.book_copies c on c.id = l.copy_id
    join public.books b on b.id = c.book_id
    left join public.profiles p on p.id = l.user_id
   where l.deposit_status = 'versee'
     and (public.is_agent() or public.is_super_admin())
     and public.agent_sees_commune(l.borrowed_at_commune_id)
   order by l.returned_at nulls last, l.deposit_at;
$$;
revoke all on function public.list_open_deposits() from public, anon;
grant execute on function public.list_open_deposits() to authenticated;
