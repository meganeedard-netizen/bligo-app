-- BliGO - Alerte agenda : récap passé de HEBDOMADAIRE à MENSUEL (17/11/2026, choix de Mégane)
-- Envoi le premier lundi du mois à 7 h, heure locale de chaque médiathèque.
-- Les tâches cron restent celles du 16/11 (toutes les heures le lundi) : c'est la
-- fonction qui ne garde que le premier lundi (jour du mois <= 7).
-- Le récap liste les événements à venir ajoutés depuis le dernier récap (10 max).

CREATE OR REPLACE FUNCTION public.queue_agenda_digest(p_force boolean DEFAULT false, p_commune_id bigint DEFAULT NULL::bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      continue when extract(isodow from v_local) <> 1 or extract(hour from v_local) <> 7
                  or extract(day from v_local) > 7;  -- premier lundi du mois seulement
      continue when c.agenda_digest_last_at is not null and c.agenda_digest_last_at > now() - interval '20 days';
    end if;

    v_since := coalesce(c.agenda_digest_last_at, now() - interval '1 month');

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
$function$;
