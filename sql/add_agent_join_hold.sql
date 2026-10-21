-- Comptoir : l'agent met un usager en file d'attente (21/10/2026)
-- ============================================================
-- Jusqu'ici, seul l'usager pouvait rejoindre la file d'attente depuis l'appli
-- (join_hold). Au comptoir, quand le livre demandé est emprunté ou mis de
-- côté pour quelqu'un d'autre, l'agent inscrit le lecteur à partir de son
-- numéro d'abonné. Mêmes règles que join_hold ; l'usager est prévenu dans
-- l'appli.

create or replace function public.agent_join_hold(p_book_id bigint, p_subscriber_number text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_book public.books;
  v_user uuid;
  v_name text;
  v_status text;
  v_position integer;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select id, full_name into v_user, v_name from public.profiles
   where subscriber_number = trim(p_subscriber_number);
  if v_user is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun usager ne porte ce numéro d''abonné.');
  end if;
  v_name := coalesce(v_name, 'L''usager');

  select * into v_book from public.books where id = p_book_id;
  if v_book.id is null then
    return jsonb_build_object('ok', false, 'message', 'Livre introuvable.');
  end if;
  if coalesce(v_book.on_site_only, false) then
    return jsonb_build_object('ok', false, 'message', 'Ce document se consulte uniquement sur place.');
  end if;
  if exists (select 1 from public.book_copies where book_id = p_book_id and status = 'available') then
    return jsonb_build_object('ok', false, 'message', 'Un exemplaire est disponible en rayon : prête-le directement.');
  end if;
  if exists (select 1 from public.reservations where book_id = p_book_id and user_id = v_user and status in ('preparation', 'pret'))
    or exists (select 1 from public.loans l join public.book_copies c on c.id = l.copy_id
               where c.book_id = p_book_id and l.user_id = v_user and l.returned_at is null) then
    return jsonb_build_object('ok', false, 'message', v_name || ' a déjà ce livre en commande ou en prêt.');
  end if;

  v_status := public.membership_status(v_user, v_book.commune_id);
  if v_status <> 'ok' then
    return jsonb_build_object('ok', false, 'message', public.membership_error_message(v_status));
  end if;

  insert into public.holds (book_id, user_id) values (p_book_id, v_user)
  on conflict do nothing;

  select count(*) into v_position from public.holds
  where book_id = p_book_id and status = 'waiting'
    and created_at <= (select created_at from public.holds where book_id = p_book_id and user_id = v_user and status = 'waiting');

  insert into public.notifications (user_id, message)
  values (v_user, 'Tu es n° ' || v_position || ' dans la file d''attente pour « ' || v_book.title || ' ». Tu seras prévenu(e) dès que le livre sera mis de côté pour toi.');

  return jsonb_build_object('ok', true, 'position', v_position, 'name', v_name,
    'message', v_name || ' est n° ' || v_position || ' dans la file d''attente. Prévenu(e) dès que le livre sera mis de côté.');
end;
$$;

revoke all on function public.agent_join_hold(bigint, text) from public, anon;
grant execute on function public.agent_join_hold(bigint, text) to authenticated;

-- Vérification : doit renvoyer agent_join_hold.
select proname from pg_proc where proname = 'agent_join_hold';
