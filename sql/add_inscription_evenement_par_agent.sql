-- BliGO : inscription à un événement faite par un agent (18/11/2026)
-- Demande de la Médiathèque Municipale de Bastia : des seniors sans appli ni
-- Internet s'inscrivent par téléphone ou sur place. L'agent les inscrit depuis
-- le logiciel, soit en retrouvant leur compte (nom ou numéro d'abonné), soit
-- comme personne sans compte (nom + téléphone). La jauge (max_seats) compte
-- toutes les inscriptions, quelle que soit leur origine, grâce au trigger
-- existant trg_enforce_event_capacity.
--
-- Le téléphone d'une personne sans compte est rangé dans une table à part,
-- lisible par les agents seulement : event_rsvps reste public en lecture
-- (compteur de places dans l'appli), il ne doit contenir aucune donnée perso.

alter table public.event_rsvps alter column user_id drop not null;
alter table public.event_rsvps add column if not exists registered_by uuid references auth.users(id) on delete set null;

create table if not exists public.event_rsvp_guests (
  rsvp_id bigint primary key references public.event_rsvps(id) on delete cascade,
  guest_name text not null check (length(trim(guest_name)) > 0),
  guest_phone text,
  created_at timestamptz not null default now()
);

alter table public.event_rsvp_guests enable row level security;

drop policy if exists "Les agents voient les inscrits sans compte" on public.event_rsvp_guests;
create policy "Les agents voient les inscrits sans compte"
  on public.event_rsvp_guests for select
  using (public.is_agent());

-- Inscription par l'agent : un compte (p_user_id) OU une personne sans compte
-- (p_guest_name, p_guest_phone).
create or replace function public.agent_add_event_rsvp(
  p_event_id bigint,
  p_user_id uuid default null,
  p_guest_name text default null,
  p_guest_phone text default null
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  if not public.is_agent() then
    raise exception 'Seul un agent peut inscrire un usager.';
  end if;
  if not exists (select 1 from public.events where id = p_event_id) then
    raise exception 'Événement introuvable.';
  end if;

  if p_user_id is not null then
    if exists (select 1 from public.event_rsvps where event_id = p_event_id and user_id = p_user_id) then
      raise exception 'Cet usager est déjà inscrit à cet événement.';
    end if;
    insert into public.event_rsvps (event_id, user_id, registered_by)
    values (p_event_id, p_user_id, auth.uid())
    returning id into v_id;
  else
    if coalesce(length(trim(p_guest_name)), 0) = 0 then
      raise exception 'Indique le nom de la personne à inscrire.';
    end if;
    insert into public.event_rsvps (event_id, user_id, registered_by)
    values (p_event_id, null, auth.uid())
    returning id into v_id;
    insert into public.event_rsvp_guests (rsvp_id, guest_name, guest_phone)
    values (v_id, trim(p_guest_name), nullif(trim(coalesce(p_guest_phone, '')), ''));
  end if;

  return v_id;
end;
$$;

create or replace function public.agent_remove_event_rsvp(p_rsvp_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_agent() then
    raise exception 'Seul un agent peut désinscrire un usager.';
  end if;
  delete from public.event_rsvps where id = p_rsvp_id;
end;
$$;

-- Liste des inscrits d'un événement, pour l'agent (compte ou sans compte).
create or replace function public.agent_event_rsvps(p_event_id bigint)
returns table (
  rsvp_id bigint,
  user_id uuid,
  full_name text,
  subscriber_number text,
  phone text,
  has_account boolean,
  checked_in boolean,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_agent() then
    raise exception 'Réservé aux agents.';
  end if;
  return query
  select er.id,
         er.user_id,
         coalesce(p.full_name, g.guest_name, 'Usager'),
         p.subscriber_number,
         g.guest_phone,
         er.user_id is not null,
         exists (select 1 from public.event_checkins c where c.event_id = er.event_id and c.user_id = er.user_id),
         er.created_at
  from public.event_rsvps er
  left join public.profiles p on p.id = er.user_id
  left join public.event_rsvp_guests g on g.rsvp_id = er.id
  where er.event_id = p_event_id
  order by coalesce(p.full_name, g.guest_name);
end;
$$;

grant execute on function public.agent_add_event_rsvp(bigint, uuid, text, text) to authenticated;
grant execute on function public.agent_remove_event_rsvp(bigint) to authenticated;
grant execute on function public.agent_event_rsvps(bigint) to authenticated;

-- Rappels : pas de notification pour une personne sans compte (user_id vide),
-- sinon l'insertion dans notifications échouerait et bloquerait tous les rappels.
create or replace function public.send_event_reminders()
returns void
language plpgsql
security definer
as $function$
begin
  insert into public.notifications (user_id, message)
  select er.user_id, 'Rappel : l''événement « ' || e.title || ' » a lieu demain' ||
    (case when e.location is not null then ' à ' || e.location else '' end) || '.'
  from public.event_rsvps er
  join public.events e on e.id = er.event_id
  where er.reminded_24h = false
    and er.user_id is not null
    and e.event_date > now()
    and e.event_date <= now() + interval '24 hours';

  update public.event_rsvps er
  set reminded_24h = true
  from public.events e
  where er.event_id = e.id
    and er.reminded_24h = false
    and e.event_date > now()
    and e.event_date <= now() + interval '24 hours';

  insert into public.notifications (user_id, message)
  select er.user_id, 'Rappel : l''événement « ' || e.title || ' » commence dans 2h' ||
    (case when e.location is not null then ' à ' || e.location else '' end) || ' !'
  from public.event_rsvps er
  join public.events e on e.id = er.event_id
  where er.reminded_2h = false
    and er.user_id is not null
    and e.event_date > now()
    and e.event_date <= now() + interval '2 hours';

  update public.event_rsvps er
  set reminded_2h = true
  from public.events e
  where er.event_id = e.id
    and er.reminded_2h = false
    and e.event_date > now()
    and e.event_date <= now() + interval '2 hours';
end;
$function$;

-- Défi « Événement culturel » : ignorer les inscrits sans compte.
create or replace function public.recheck_evenement_culturel_defi()
returns void
language plpgsql
security definer
as $function$
declare
  r record;
begin
  for r in
    select distinct er.user_id
    from public.event_rsvps er
    join public.events e on e.id = er.event_id
    where e.event_date < now()
      and er.user_id is not null
      and not exists (
        select 1 from public.defis_completed dc
        where dc.user_id = er.user_id and dc.defi_code = 'evenement_culturel'
      )
  loop
    perform public.check_defis(r.user_id);
  end loop;
end;
$function$;
