-- BliGO, 24/11/2026 (précision de Mégane) : la médiathèque n'encaisse pas, c'est la
-- régie (PayFiP ensuite). L'agent note seulement un paiement déjà reçu par la régie.
alter table public.payments drop constraint if exists payments_method_check;
alter table public.payments add constraint payments_method_check check (method in ('regie', 'especes', 'carte', 'cheque', 'virement', 'payfip', 'gratuit'));
create or replace function public.trg_paid_event_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce((select price_cents from public.events where id = new.event_id), 0) > 0
     and current_setting('bligo.paiement_ok', true) is distinct from '1' then
    raise exception 'Cet événement est payant : ta place est confirmée dès que ton paiement est enregistré.';
  end if;
  return new;
end $$;
drop function if exists public.agent_paid_event_rsvp(bigint, integer, text, uuid, text, text, text, text);
create or replace function public.agent_paid_event_rsvp(p_event_id bigint, p_amount_cents integer, p_method text, p_user_id uuid default null,
  p_guest_name text default null, p_guest_phone text default null, p_guest_genre text default null, p_guest_age text default null, p_reference text default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_rsvp bigint; v_pay bigint;
begin
  perform set_config('bligo.paiement_ok', '1', true);
  v_rsvp := public.agent_add_event_rsvp(p_event_id, p_user_id, p_guest_name, p_guest_phone, p_guest_genre, p_guest_age);
  perform set_config('bligo.paiement_ok', '', true);
  select id into v_pay from public.payments where rsvp_id = v_rsvp;
  perform public.settle_payment(v_pay, 'paye', p_method, p_amount_cents, p_reference);
  return v_rsvp;
end $$;
revoke all on function public.agent_paid_event_rsvp(bigint, integer, text, uuid, text, text, text, text, text) from public, anon;
grant execute on function public.agent_paid_event_rsvp(bigint, integer, text, uuid, text, text, text, text, text) to authenticated;
drop function if exists public.add_membership_payment(uuid, integer, text);
create or replace function public.add_membership_payment(p_user_id uuid, p_amount_cents integer, p_method text, p_reference text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_agent() then raise exception 'Réservé aux agents.'; end if;
  insert into public.payments (commune_id, user_id, kind, label, amount_cents, status, method, reference, recorded_by, paid_at)
  values (public.agent_commune_id(), p_user_id, 'adhesion', 'Adhésion annuelle', p_amount_cents, 'paye', p_method, p_reference, auth.uid(), now());
end $$;
revoke all on function public.add_membership_payment(uuid, integer, text, text) from public, anon;
grant execute on function public.add_membership_payment(uuid, integer, text, text) to authenticated;
