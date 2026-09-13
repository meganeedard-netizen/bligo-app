
-- Rappels automatiques pour les événements de l'agenda culturel : la veille,
-- puis 2h avant, pour chaque usager inscrit (RSVP).

alter table public.event_rsvps add column if not exists reminded_24h boolean not null default false;
alter table public.event_rsvps add column if not exists reminded_2h boolean not null default false;

create or replace function public.send_event_reminders()
returns void
language plpgsql
security definer
as $$
begin
  -- Rappel la veille (dans les 24h à venir, pas encore envoyé)
  insert into public.notifications (user_id, message)
  select er.user_id, 'Rappel : l''événement « ' || e.title || ' » a lieu demain' ||
    (case when e.location is not null then ' à ' || e.location else '' end) || '.'
  from public.event_rsvps er
  join public.events e on e.id = er.event_id
  where er.reminded_24h = false
    and e.event_date > now()
    and e.event_date <= now() + interval '24 hours';

  update public.event_rsvps er
  set reminded_24h = true
  from public.events e
  where er.event_id = e.id
    and er.reminded_24h = false
    and e.event_date > now()
    and e.event_date <= now() + interval '24 hours';

  -- Rappel 2h avant
  insert into public.notifications (user_id, message)
  select er.user_id, 'Rappel : l''événement « ' || e.title || ' » commence dans 2h' ||
    (case when e.location is not null then ' à ' || e.location else '' end) || ' !'
  from public.event_rsvps er
  join public.events e on e.id = er.event_id
  where er.reminded_2h = false
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
$$;

select cron.schedule('event-reminders', '*/15 * * * *', $$select public.send_event_reminders();$$);
