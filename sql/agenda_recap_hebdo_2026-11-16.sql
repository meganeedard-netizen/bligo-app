-- BliGO - Alerte agenda : récap hebdomadaire par e-mail (16/11/2026)
--
-- Demande du Sud Corse (RDV du 12/11/2026) : prévenir les usagers quand la
-- Médiathèque Municipale ajoute des événements à son agenda. Choix de Mégane :
-- un seul e-mail récapitulatif par semaine (pas un mail par événement) pour
-- limiter les envois.
--
-- - profiles.agenda_digest : l'usager peut se désabonner (Profil > Modifier
--   mon profil > Récap de l'agenda). Abonné par défaut.
-- - communes.agenda_digest_last_at : date du dernier récap de la médiathèque.
-- - queue_agenda_digest() : chaque lundi à 7 h, heure locale de chaque
--   médiathèque (communes.timezone), met en file (email_outbox) un e-mail
--   pour chaque usager si des événements à venir ont été ajoutés depuis le
--   dernier récap. Rien n'est envoyé s'il n'y a rien de nouveau.
-- - Le lundi, la file d'e-mails est vidée toutes les heures (en plus de
--   l'envoi quotidien) pour que le récap arrive le matin partout.
--
-- Dans l'appli, la pastille de l'onglet Agenda et l'étiquette « Nouveau »
-- sont calculées sur le téléphone (js/navBadge.js), sans SQL.

alter table public.profiles add column if not exists agenda_digest boolean not null default true;
alter table public.communes add column if not exists agenda_digest_last_at timestamptz;

-- Date lisible en français, à l'heure de la médiathèque (lc_time du serveur en anglais).
create or replace function public.fr_event_date(p_ts timestamptz, p_tz text)
returns text
language sql
stable
as $$
  select (array['Dimanche','Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi'])[extract(dow from l)::int + 1]
      || ' ' || extract(day from l)::int
      || ' ' || (array['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'])[extract(month from l)::int]
      || ' à ' || to_char(l, 'FMHH24"h"MI')
  from (select p_ts at time zone coalesce(p_tz, 'America/Guadeloupe') as l) x;
$$;

-- p_force : pour un test ou un envoi manuel (ignore lundi 7 h et la semaine écoulée).
create or replace function public.queue_agenda_digest(p_force boolean default false, p_commune_id bigint default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  c record;
  u record;
  v_local timestamp;
  v_since timestamptz;
  v_list text;
  v_nb integer;
  v_total integer := 0;
begin
  for c in
    select * from public.communes
    where (p_commune_id is null or id = p_commune_id)
  loop
    v_local := now() at time zone coalesce(c.timezone, 'America/Guadeloupe');
    if not p_force then
      continue when extract(isodow from v_local) <> 1 or extract(hour from v_local) <> 7;
      continue when c.agenda_digest_last_at is not null and c.agenda_digest_last_at > now() - interval '6 days';
    end if;

    v_since := coalesce(c.agenda_digest_last_at, now() - interval '7 days');

    select count(*),
           string_agg(
             '• ' || coalesce(e.event_type, 'Événement') || coalesce(' : ' || nullif(trim(e.title), ''), '')
             || E'\n  ' || public.fr_event_date(e.event_date, c.timezone)
             || coalesce(', ' || nullif(trim(e.location), ''), ''),
             E'\n\n' order by e.event_date)
      into v_nb, v_list
      from (select * from public.events
             where commune_id = c.id and created_at > v_since and event_date > now()
             order by event_date limit 10) e;

    update public.communes set agenda_digest_last_at = now() where id = c.id;
    continue when coalesce(v_nb, 0) = 0;

    for u in
      select p.id, nullif(split_part(trim(coalesce(p.full_name, '')), ' ', 1), '') as prenom, au.email
        from public.profiles p
        join auth.users au on au.id = p.id
       where p.commune_id = c.id
         and p.agenda_digest
         and p.app_access_closed_at is null
         and coalesce(p.registration_status, '') in ('valide', 'pre_inscrit')
         and au.email is not null
    loop
      insert into public.email_outbox (to_email, to_name, subject, body_text)
      values (u.email, u.prenom,
        'Du nouveau à l''agenda de ta Médiathèque Municipale',
        'Bonjour' || coalesce(' ' || u.prenom, '') || E',\n\n'
        || 'Bonne nouvelle, ta Médiathèque Municipale a ajouté '
        || case when v_nb = 1 then 'un événement' else v_nb || ' événements' end
        || E' à son agenda :\n\n' || v_list
        || E'\n\nInscris-toi en un clic dans l''onglet Agenda de l''appli BliGO : https://bligo.app/agenda.html'
        || E'\n\nÀ bientôt !\nTa Médiathèque Municipale · ' || c.name
        || E'\n\n--\nTu ne veux plus recevoir ce récap ? Désactive-le dans l''appli : Profil > Modifier mon profil > Récap de l''agenda.');
      v_total := v_total + 1;
    end loop;
  end loop;
  return v_total;
end;
$$;

revoke all on function public.queue_agenda_digest(boolean, bigint) from public, anon, authenticated;

-- Toutes les heures le lundi : la fonction ne garde que les médiathèques où il est 7 h.
do $$
begin
  perform cron.unschedule('agenda-digest') where exists (select 1 from cron.job where jobname = 'agenda-digest');
  perform cron.schedule('agenda-digest', '2 * * * 1', 'select public.queue_agenda_digest();');

  -- Envoi de la file toutes les heures le lundi (même commande que l'envoi quotidien,
  -- recopiée depuis cron.job pour ne pas écrire la clé ici).
  perform cron.unschedule('send-queued-emails-lundi') where exists (select 1 from cron.job where jobname = 'send-queued-emails-lundi');
  perform cron.schedule('send-queued-emails-lundi', '12 * * * 1',
    (select command from cron.job where jobname = 'send-queued-emails'));
end $$;
