-- BliGO, connexion CAS aux ressources numériques (23/11/2026). Inactif tant
-- qu'une ressource n'a pas d'adresse CAS (cas_service_prefix).
alter table public.digital_resources add column if not exists cas_service_prefix text;
do $$ begin
  -- Adresse https, domaine complet suivi d'un « / » : évite qu'un autre site au nom proche reçoive un ticket.
  alter table public.digital_resources add constraint digital_resources_cas_prefix_check
    check (cas_service_prefix is null or cas_service_prefix ~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?/');
exception when duplicate_object then null; end $$;
create table if not exists public.cas_identities (
  user_id uuid not null references auth.users(id) on delete cascade,
  resource_id bigint not null references public.digital_resources(id) on delete cascade,
  opaque_id uuid not null default gen_random_uuid(),
  primary key (user_id, resource_id)
);
create table if not exists public.cas_tickets (
  ticket text primary key, service text not null, opaque_id uuid not null,
  expires_at timestamptz not null default now() + interval '60 seconds'
);
alter table public.cas_identities enable row level security;
alter table public.cas_tickets enable row level security;
revoke all on public.cas_identities, public.cas_tickets from anon, authenticated;

create or replace function public.cas_issue_ticket(p_service text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare r public.digital_resources; v_id uuid; v_ticket text; v_p record; v_hash text := ''; v_base text := p_service;
begin
  if auth.uid() is null then return null; end if;
  select commune_id, registration_status, membership_expires_at into v_p from public.profiles where id = auth.uid();
  if v_p.registration_status is distinct from 'valide'
     or (v_p.membership_expires_at is not null and v_p.membership_expires_at <= now()) then return null; end if;
  select * into r from public.digital_resources d
   where d.commune_id = v_p.commune_id and d.active and (d.expires_on is null or d.expires_on >= current_date)
     and d.cas_service_prefix is not null and left(p_service, length(d.cas_service_prefix)) = d.cas_service_prefix
   order by length(d.cas_service_prefix) desc limit 1;
  if r.id is null then return null; end if;
  insert into public.cas_identities (user_id, resource_id) values (auth.uid(), r.id) on conflict do nothing;
  select opaque_id into v_id from public.cas_identities where user_id = auth.uid() and resource_id = r.id;
  v_ticket := 'ST-' || encode(gen_random_bytes(24), 'hex');
  delete from public.cas_tickets where expires_at < now() - interval '1 hour';
  insert into public.cas_tickets (ticket, service, opaque_id) values (v_ticket, p_service, v_id);
  if position('#' in v_base) > 0 then
    v_hash := substr(v_base, position('#' in v_base)); v_base := left(v_base, position('#' in v_base) - 1);
  end if;
  return v_base || case when position('?' in v_base) > 0 then '&' else '?' end || 'ticket=' || v_ticket || v_hash;
end $$;
create or replace function public.cas_consume_ticket(p_ticket text, p_service text) returns uuid
language sql security definer set search_path = public as $$
  with t as (delete from public.cas_tickets where ticket = p_ticket returning *)
  select opaque_id from t where service = p_service and expires_at > now();
$$;
revoke all on function public.cas_issue_ticket(text) from public, anon;
grant execute on function public.cas_issue_ticket(text) to authenticated;
revoke all on function public.cas_consume_ticket(text, text) from public, anon, authenticated;
grant execute on function public.cas_consume_ticket(text, text) to service_role;
