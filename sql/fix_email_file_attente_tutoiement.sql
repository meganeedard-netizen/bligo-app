-- Complément du 19/10/2026 à file_attente_remise_en_rayon.sql
-- (ajouté au fichier après la première exécution) : e-mail envoyé à
-- l'usager en file d'attente, au tutoiement.

-- 5. E-mail « Ton livre est arrivé » au tutoiement (il part maintenant à chaque
--    « Préparer pour X ») ; le reste de la fonction est inchangé.
create or replace function public.promote_next_hold(p_copy_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_hold public.holds;
  v_reservation_id bigint;
  v_title text;
  v_email text;
  v_name text;
begin
  select * into v_copy from public.book_copies where id = p_copy_id;
  if v_copy.id is null then
    return false;
  end if;
  select title into v_title from public.books where id = v_copy.book_id;

  for v_hold in
    select * from public.holds where book_id = v_copy.book_id and status = 'waiting' order by created_at
  loop
    begin
      insert into public.reservations (user_id, book_id, status, pickup_commune_id)
      values (v_hold.user_id, v_copy.book_id, 'preparation', v_copy.current_commune_id)
      returning id into v_reservation_id;

      update public.book_copies set status = 'reserved' where id = v_copy.id;
      update public.reservations set status = 'pret' where id = v_reservation_id;
      update public.holds set status = 'promoted', reservation_id = v_reservation_id, promoted_at = now() where id = v_hold.id;

      select u.email, p.full_name into v_email, v_name
      from auth.users u left join public.profiles p on p.id = u.id where u.id = v_hold.user_id;
      if v_email is not null and to_regclass('public.email_outbox') is not null then
        insert into public.email_outbox (to_email, to_name, subject, body_text)
        values (v_email, v_name, 'Ton livre est arrivé : « ' || coalesce(v_title, '') || ' »',
          'Bonjour' || coalesce(' ' || v_name, '') || E',\n\nLe livre « ' || coalesce(v_title, '') ||
          E' » que tu attendais est revenu : il est mis de côté pour toi à la Médiathèque Municipale.\n' ||
          E'Tu as 48 heures pour venir le chercher, passé ce délai il sera proposé à la personne suivante.\n\nÀ bientôt,\nTa Médiathèque Municipale');
      end if;
      return true;
    exception when others then
      update public.holds set status = 'skipped' where id = v_hold.id;
      insert into public.notifications (user_id, message)
      values (v_hold.user_id, '« ' || coalesce(v_title, '') || ' » que tu attendais est revenu, mais il n''a pas pu être mis de côté pour toi (' || sqlerrm || '). Il passe à la personne suivante.');
    end;
  end loop;
  return false;
end;
$$;

-- Vérification : doit renvoyer « Ton livre est arrivé ».
select substring(prosrc from 'Ton livre est arrivé') as verification
  from pg_proc where proname = 'promote_next_hold';
