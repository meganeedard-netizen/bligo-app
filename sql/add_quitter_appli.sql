-- « Supprimer mon accès à l'appli » (23/10/2026, validé par Mégane).
-- L'usager quitte l'appli mais reste abonné à sa médiathèque.
--
-- Disparaît (propre à l'appli) : liste d'envie, points de fidélité, badges,
-- défis, notifications, avis publiés, réglages de masquage d'avis, connexion.
-- Reste dans le logiciel agent : fiche d'abonné, carte, historique, emprunts
-- et réservations en cours, dettes, inscriptions aux événements.
-- Possible même avec des documents encore empruntés.
--
-- L'agent peut rouvrir l'accès depuis la fiche usager (reopen_app_access).
-- La suppression complète reste delete_my_account (add_suppression_compte_immediate.sql).

alter table public.profiles add column if not exists app_access_closed_at timestamptz;

create or replace function public.leave_app()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'message', 'Tu dois être connecté.');
  end if;
  if exists (select 1 from public.profiles where id = uid and role in ('agent', 'super_admin')) then
    return jsonb_build_object('ok', false, 'message', 'Un compte agent ne peut pas être fermé depuis l''appli. Écris-nous à megane@bligo.fr.');
  end if;

  delete from public.wishlist where user_id = uid;
  delete from public.notifications where user_id = uid;
  delete from public.defis_completed where user_id = uid;
  delete from public.book_reviews where user_id = uid;
  delete from public.review_author_mutes where user_id = uid;
  delete from public.review_reports where reporter_id = uid;

  update public.profiles set loyalty_points = 0, app_access_closed_at = now() where id = uid;
  -- Badges : colonnes ajoutées par une migration plus ancienne.
  begin
    update public.profiles set badge_tier = 0, plume_locale_unlocked = false where id = uid;
  exception when undefined_column then null;
  end;

  -- Plus de connexion possible, et déconnexion de tous ses appareils.
  update auth.users set banned_until = 'infinity' where id = uid;
  delete from auth.sessions where user_id = uid;

  return jsonb_build_object('ok', true, 'message', 'Ton accès à l''appli est fermé. Tu restes inscrit à ta médiathèque.');
end;
$$;

revoke all on function public.leave_app() from public, anon;
grant execute on function public.leave_app() to authenticated;

-- Rouvrir l'accès à l'appli depuis la fiche usager du logiciel agent.
create or replace function public.reopen_app_access(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  update auth.users set banned_until = null where id = p_user_id;
  update public.profiles set app_access_closed_at = null where id = p_user_id;
end;
$$;

revoke all on function public.reopen_app_access(uuid) from public, anon;
grant execute on function public.reopen_app_access(uuid) to authenticated;
