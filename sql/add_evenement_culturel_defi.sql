-- Active le défi "Événement Culturel" (17/09/2026)
-- ============================================================
-- Le code 'evenement_culturel' existait déjà dans la contrainte de
-- defis_completed.defi_code, avec une fonction record_event_checkin()
-- jamais appelée nulle part dans l'appli (aucun pointage de présence à
-- l'entrée d'un événement) — le défi n'était donc jamais réussi.
--
-- Nouvelle règle demandée par Mégane : présent à 5 événements culturels.
-- Faute d'un vrai pointage de présence, on l'approxime avec une inscription
-- (event_rsvps) à un événement dont la date est déjà passée.

create or replace function public.check_defis(p_user_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_donations_30d integer;
  v_reviews_count integer;
  v_read_count integer;
  v_events_attended integer;
begin
  select count(*) into v_donations_30d
  from public.free_books
  where donated_by = p_user_id and created_at >= now() - interval '30 days';

  if v_donations_30d >= 5 and not exists (select 1 from public.defis_completed where user_id = p_user_id and defi_code = 'vide_bibliotheque') then
    insert into public.defis_completed (user_id, defi_code) values (p_user_id, 'vide_bibliotheque');
    update public.profiles set loyalty_points = loyalty_points + 100 where id = p_user_id;
    insert into public.notifications (user_id, message)
    values (p_user_id, '🎉 Défi « Vide-Bibliothèque » réussi ! 5 dons en 30 jours — vous gagnez 100 points de fidélité.');
    perform public.check_and_award_badges(p_user_id);
  end if;

  select count(*) into v_reviews_count from public.book_reviews where user_id = p_user_id;
  if v_reviews_count >= 3 and not exists (select 1 from public.defis_completed where user_id = p_user_id and defi_code = 'critique_litteraire') then
    insert into public.defis_completed (user_id, defi_code) values (p_user_id, 'critique_litteraire');
    update public.profiles set loyalty_points = loyalty_points + 50 where id = p_user_id;
    insert into public.notifications (user_id, message)
    values (p_user_id, '🎉 Défi « Critique Littéraire » réussi ! 3 avis déposés — vous gagnez 50 points de fidélité.');
    perform public.check_and_award_badges(p_user_id);
  end if;

  select count(*) into v_read_count from public.reservations where user_id = p_user_id and status = 'recupere';
  if v_read_count >= 10 and not exists (select 1 from public.defis_completed where user_id = p_user_id and defi_code = 'marathon_10_livres') then
    insert into public.defis_completed (user_id, defi_code) values (p_user_id, 'marathon_10_livres');
    update public.profiles set loyalty_points = loyalty_points + 100 where id = p_user_id;
    insert into public.notifications (user_id, message)
    values (p_user_id, '🎉 Défi « Marathon 10 Livres » réussi ! 10 livres lus — vous gagnez 100 points de fidélité.');
    perform public.check_and_award_badges(p_user_id);
  end if;

  select count(*) into v_events_attended
  from public.event_rsvps er
  join public.events e on e.id = er.event_id
  where er.user_id = p_user_id and e.event_date < now();

  if v_events_attended >= 5 and not exists (select 1 from public.defis_completed where user_id = p_user_id and defi_code = 'evenement_culturel') then
    insert into public.defis_completed (user_id, defi_code) values (p_user_id, 'evenement_culturel');
    update public.profiles set loyalty_points = loyalty_points + 80 where id = p_user_id;
    insert into public.notifications (user_id, message)
    values (p_user_id, '🎉 Défi « Événement Culturel » réussi ! Présent à 5 événements — vous gagnez 80 points de fidélité.');
    perform public.check_and_award_badges(p_user_id);
  end if;
end;
$$;

-- Pas d'action ponctuelle à laquelle accrocher ce défi (contrairement aux 3
-- autres) : la présence ne se sait qu'une fois la date de l'événement passée.
-- Un recalcul quotidien suffit.
create or replace function public.recheck_evenement_culturel_defi()
returns void
language plpgsql
security definer
as $$
declare
  r record;
begin
  for r in
    select distinct er.user_id
    from public.event_rsvps er
    join public.events e on e.id = er.event_id
    where e.event_date < now()
      and not exists (
        select 1 from public.defis_completed dc
        where dc.user_id = er.user_id and dc.defi_code = 'evenement_culturel'
      )
  loop
    perform public.check_defis(r.user_id);
  end loop;
end;
$$;

select cron.schedule('recheck-evenement-culturel-defi', '0 5 * * *', $$select public.recheck_evenement_culturel_defi();$$);

-- Recalcul immédiat pour les usagers déjà éligibles aujourd'hui.
select public.recheck_evenement_culturel_defi();
