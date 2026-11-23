-- BliGO, 23/11/2026 (précisions de Mégane)
-- 1. Panier = compte connecté ; agent ajusté si l'ordinateur est partagé.
create or replace function public.commune_agents() returns table (id uuid, full_name text)
language sql stable security definer set search_path = public as $$
  select p.id, p.full_name from public.profiles p
   where public.is_agent() and p.role in ('agent', 'super_admin') and p.commune_id = public.agent_commune_id() order by p.full_name;
$$;
revoke all on function public.commune_agents() from public, anon;
grant execute on function public.commune_agents() to authenticated;
create or replace function public.set_book_cataloger(p_book_id bigint, p_agent uuid, p_lot text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_agent() then raise exception 'Réservé aux agents.'; end if;
  if p_agent <> auth.uid() and not exists (select 1 from public.books b join public.profiles p on p.commune_id = b.commune_id
      where b.id = p_book_id and p.id = p_agent and p.role in ('agent', 'super_admin')) then
    raise exception 'Cet agent n''est pas de la médiathèque.';
  end if;
  -- Seulement la notice que ce compte vient d'ajouter.
  update public.book_catalogers set agent_id = p_agent, lot = nullif(trim(p_lot), '') where book_id = p_book_id and agent_id = auth.uid();
end $$;
revoke all on function public.set_book_cataloger(bigint, uuid, text) from public, anon;
grant execute on function public.set_book_cataloger(bigint, uuid, text) to authenticated;
drop function if exists public.rename_catalog_lot(text, text);

-- 2. Événement payant : pas de place sans paiement.
do $$ begin perform cron.unschedule('release-unpaid-seats'); exception when others then null; end $$;
drop function if exists public.release_unpaid_seats();
create or replace function public.trg_paid_event_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce((select price_cents from public.events where id = new.event_id), 0) > 0
     and current_setting('bligo.paiement_ok', true) is distinct from '1' then
    raise exception 'Cet événement est payant : ta place est confirmée au moment du paiement, à l''accueil de ta médiathèque.';
  end if;
  return new;
end $$;
drop trigger if exists trg_event_rsvps_paid_guard on public.event_rsvps;
create trigger trg_event_rsvps_paid_guard before insert on public.event_rsvps for each row execute function public.trg_paid_event_guard();
-- Inscription + paiement en une seule opération : tout passe ou rien ne passe.
create or replace function public.agent_paid_event_rsvp(p_event_id bigint, p_amount_cents integer, p_method text, p_user_id uuid default null,
  p_guest_name text default null, p_guest_phone text default null, p_guest_genre text default null, p_guest_age text default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_rsvp bigint; v_pay bigint;
begin
  perform set_config('bligo.paiement_ok', '1', true);
  v_rsvp := public.agent_add_event_rsvp(p_event_id, p_user_id, p_guest_name, p_guest_phone, p_guest_genre, p_guest_age);
  perform set_config('bligo.paiement_ok', '', true);
  select id into v_pay from public.payments where rsvp_id = v_rsvp;
  perform public.settle_payment(v_pay, 'paye', p_method, p_amount_cents);
  return v_rsvp;
end $$;
revoke all on function public.agent_paid_event_rsvp(bigint, integer, text, uuid, text, text, text, text) from public, anon;
grant execute on function public.agent_paid_event_rsvp(bigint, integer, text, uuid, text, text, text, text) to authenticated;
