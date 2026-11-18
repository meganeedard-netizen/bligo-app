-- BliGO : bilan annuel de l'agenda culturel (18/11/2026, demande des Abymes).
-- Public par genre et par âge, remplissage, types d'événements, répétitions,
-- comparaison avec l'année précédente. Totaux seulement, jamais de noms.
--
-- 1. Personnes inscrites SANS compte : genre + tranche d'âge (facultatifs),
--    pour qu'elles comptent aussi dans le bilan.
-- 2. agent_add_event_rsvp accepte ces deux champs.
-- 3. agenda_bilan(commune, année) : tout le bilan en un seul jsonb.

alter table public.event_rsvp_guests add column if not exists genre text;
alter table public.event_rsvp_guests add column if not exists age_group text;
alter table public.event_rsvp_guests drop constraint if exists event_rsvp_guests_genre_valide;
alter table public.event_rsvp_guests add constraint event_rsvp_guests_genre_valide
  check (genre is null or genre in ('femme', 'homme', 'transgenre', 'non_precise'));
alter table public.event_rsvp_guests drop constraint if exists event_rsvp_guests_age_valide;
alter table public.event_rsvp_guests add constraint event_rsvp_guests_age_valide
  check (age_group is null or age_group in ('enfant', 'adulte', 'senior'));

-- L'ancienne version à 4 paramètres est remplacée (sinon appel ambigu).
drop function if exists public.agent_add_event_rsvp(bigint, uuid, text, text);

create or replace function public.agent_add_event_rsvp(
  p_event_id bigint,
  p_user_id uuid default null,
  p_guest_name text default null,
  p_guest_phone text default null,
  p_guest_genre text default null,
  p_guest_age text default null
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
    insert into public.event_rsvp_guests (rsvp_id, guest_name, guest_phone, genre, age_group)
    values (v_id, trim(p_guest_name), nullif(trim(coalesce(p_guest_phone, '')), ''),
            nullif(p_guest_genre, ''), nullif(p_guest_age, ''));
  end if;

  return v_id;
end;
$$;

grant execute on function public.agent_add_event_rsvp(bigint, uuid, text, text, text, text) to authenticated;

-- Bilan de l'année p_year pour la médiathèque p_commune_id.
-- Public d'un événement : les présents pointés s'il y en a, sinon les inscrits
-- (comptes + personnes sans compte). « Public touché » = participants saisis,
-- sinon le plus grand de présents / inscrits (même règle que Néoscrib).
create or replace function public.agenda_bilan(p_commune_id bigint, p_year integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz text;
  v_start timestamptz;
  v_end timestamptz;
  v_prev_start timestamptz;
  v jsonb;
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction';
  end if;

  select coalesce(c.timezone, 'UTC') into v_tz from public.communes c where c.id = p_commune_id;
  v_start := make_timestamptz(p_year, 1, 1, 0, 0, 0, coalesce(v_tz, 'UTC'));
  v_end := make_timestamptz(p_year + 1, 1, 1, 0, 0, 0, coalesce(v_tz, 'UTC'));
  v_prev_start := make_timestamptz(p_year - 1, 1, 1, 0, 0, 0, coalesce(v_tz, 'UTC'));

  with ev as (
    select e.id, e.title, e.event_date, coalesce(nullif(e.event_type, ''), 'Autre') as event_type,
           coalesce(e.audience, 'tous') as audience, e.max_seats, e.participants,
           (select count(*) from public.event_rsvps r where r.event_id = e.id) as inscrits,
           (select count(*) from public.event_checkins c where c.event_id = e.id) as presents
      from public.events e
     where e.commune_id = p_commune_id
       and e.event_date >= v_start and e.event_date < v_end
  ),
  ev2 as (
    select ev.*,
           coalesce(ev.participants, greatest(ev.presents, ev.inscrits)) as public_touche,
           ev.event_date < now() as passe
      from ev
  ),
  -- Personnes identifiées : présents pointés si l'événement en a, sinon inscrits.
  personnes as (
    select e.id as event_id, c.user_id, null::bigint as rsvp_id
      from ev2 e join public.event_checkins c on c.event_id = e.id
     where e.presents > 0
    union all
    select e.id, r.user_id, r.id
      from ev2 e join public.event_rsvps r on r.event_id = e.id
     where e.presents = 0
  ),
  profil as (
    select pe.event_id, pe.user_id,
           coalesce(p.genre, g.genre) as genre,
           coalesce(p.age_group, g.age_group,
                    case p.tariff_category when 'mineur' then 'enfant' when 'majeur' then 'adulte' end) as age
      from personnes pe
      left join public.profiles p on p.id = pe.user_id
      left join public.event_rsvp_guests g on g.rsvp_id = pe.rsvp_id
  ),
  prev as (
    select count(*) as n,
           coalesce(sum(coalesce(e.participants, greatest(
             (select count(*) from public.event_checkins c where c.event_id = e.id),
             (select count(*) from public.event_rsvps r where r.event_id = e.id)))), 0) as public_touche
      from public.events e
     where e.commune_id = p_commune_id
       and e.event_date >= v_prev_start and e.event_date < v_start
  )
  select jsonb_build_object(
    'annee', p_year,
    'totaux', (select jsonb_build_object(
        'evenements', count(*),
        'passes', count(*) filter (where passe),
        'public_touche', coalesce(sum(public_touche), 0),
        'inscrits', coalesce(sum(inscrits), 0),
        'presents', coalesce(sum(presents), 0),
        'places', coalesce(sum(max_seats) filter (where max_seats > 0), 0),
        'inscrits_jauge', coalesce(sum(inscrits) filter (where max_seats > 0), 0),
        'complets', count(*) filter (where max_seats > 0 and inscrits >= max_seats),
        'jeunesse', count(*) filter (where audience = 'enfants'))
      from ev2),
    'annee_precedente', (select jsonb_build_object('evenements', n, 'public_touche', public_touche) from prev),
    'personnes_uniques', (select count(distinct user_id) from profil where user_id is not null),
    'fideles', (select count(*) from (select user_id from profil where user_id is not null
                                       group by user_id having count(distinct event_id) >= 2) f),
    'genre', coalesce((select jsonb_object_agg(k, n) from (
        select coalesce(genre, 'non_renseigne') as k, count(*) as n from profil group by 1) s), '{}'::jsonb),
    'age', coalesce((select jsonb_object_agg(k, n) from (
        select coalesce(age, 'non_renseigne') as k, count(*) as n from profil group by 1) s), '{}'::jsonb),
    'par_type', coalesce((select jsonb_agg(jsonb_build_object('type', event_type, 'n', n, 'public', pub) order by n desc, pub desc) from (
        select event_type, count(*) as n, coalesce(sum(public_touche), 0) as pub from ev2 group by 1) s), '[]'::jsonb),
    'par_mois', coalesce((select jsonb_agg(jsonb_build_object('mois', m, 'n', n, 'public', pub) order by m) from (
        select extract(month from event_date at time zone coalesce(v_tz, 'UTC'))::int as m,
               count(*) as n, coalesce(sum(public_touche), 0) as pub
          from ev2 group by 1) s), '[]'::jsonb),
    'repetes', coalesce((select jsonb_agg(jsonb_build_object('titre', titre, 'n', n, 'public', pub) order by n desc) from (
        select min(title) as titre, count(*) as n, coalesce(sum(public_touche), 0) as pub
          from ev2 group by lower(trim(title)) having count(*) >= 2) s), '[]'::jsonb),
    'evenements', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'titre', title, 'date', event_date, 'type', event_type, 'audience', audience,
        'places', max_seats, 'inscrits', inscrits, 'presents', presents,
        'participants', participants, 'public', public_touche, 'passe', passe) order by event_date)
      from ev2), '[]'::jsonb)
  ) into v;

  return v;
end;
$$;

grant execute on function public.agenda_bilan(bigint, integer) to authenticated;
