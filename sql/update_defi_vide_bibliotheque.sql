-- Défi "Vide-Bibliothèque" plus réaliste : 3 dons dans l'année (au lieu de 5 en 30 jours).

create or replace function public.check_defis(p_user_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_donations_1y integer;
  v_reviews_count integer;
  v_read_count integer;
begin
  select count(*) into v_donations_1y
  from public.free_books
  where donated_by = p_user_id and created_at >= now() - interval '1 year';

  if v_donations_1y >= 3 and not exists (select 1 from public.defis_completed where user_id = p_user_id and defi_code = 'vide_bibliotheque') then
    insert into public.defis_completed (user_id, defi_code) values (p_user_id, 'vide_bibliotheque');
    update public.profiles set loyalty_points = loyalty_points + 100 where id = p_user_id;
    insert into public.notifications (user_id, message)
    values (p_user_id, '🎉 Défi « Vide-Bibliothèque » réussi ! 3 dons dans l''année — vous gagnez 100 points de fidélité.');
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
end;
$$;
