-- À LANCER UNE FOIS dans Supabase > SQL Editor (23/10/2026).
-- Regroupe tout ce qui manque : on peut le relancer sans risque.

-- =====================================================================
-- 1. Statistiques de prêt gardées sans nom (23/10/2026)
-- Quand un usager supprime complètement son compte, ses emprunts rendus et ses
-- réservations retirées ne sont plus effacés : ils restent, sans aucun lien
-- avec la personne (user_id vidé), pour que les chiffres de prêt de la
-- médiathèque restent justes.
-- =====================================================================
do $$
declare
  t text;
  c record;
begin
  foreach t in array array['loans', 'reservations'] loop
    execute format('alter table public.%I alter column user_id drop not null', t);
    for c in
      select con.conname from pg_constraint con
      join pg_attribute a on a.attrelid = con.conrelid and a.attnum = con.conkey[1]
      where con.conrelid = ('public.' || t)::regclass and con.contype = 'f' and a.attname = 'user_id'
    loop
      execute format('alter table public.%I drop constraint %I', t, c.conname);
    end loop;
    execute format('alter table public.%I add constraint %I foreign key (user_id) references auth.users(id) on delete set null', t, t || '_user_id_fkey');
  end loop;
end $$;

-- =====================================================================
-- 2. Suppression complète du compte depuis l'appli
-- =====================================================================
-- Suppression immédiate de son compte par l'usager, depuis l'appli (23/10/2026).
-- Remplace la demande par e-mail « traitée sous un mois ». Apple exige que la
-- suppression se fasse dans l'appli (règle 5.1.1 v).
--
-- Conditions : aucun document en cours d'emprunt et aucune dette ouverte
-- (document perdu ou abîmé non réglé). Sinon, message clair et rien n'est supprimé.
--
-- Ce qui disparaît : le compte de connexion, le profil, et tout ce qui est
-- rattaché à l'usager avec « on delete cascade » (liste d'envie, avis,
-- inscriptions aux événements...). Les emprunts rendus et réservations
-- retirées restent SANS NOM pour les statistiques de prêt (23/10/2026).
-- Les autres traces où le compte apparaît (ex. « parrainé par », « don de »)
-- sont vidées (mises à null) pour ne pas bloquer la suppression.

create or replace function public.delete_my_account()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
  fk record;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'message', 'Tu dois être connecté pour supprimer ton compte.');
  end if;

  -- Les comptes agents et administrateurs ne se suppriment pas depuis l'appli.
  if exists (select 1 from public.profiles where id = uid and role in ('agent', 'super_admin')) then
    return jsonb_build_object('ok', false, 'message', 'Un compte agent ne peut pas être supprimé depuis l''appli. Écris-nous à megane@bligo.fr.');
  end if;

  if exists (select 1 from public.loans where user_id = uid and returned_at is null) then
    return jsonb_build_object('ok', false, 'message', 'Tu as encore des documents empruntés. Rends-les à la médiathèque, puis tu pourras supprimer ton compte.');
  end if;

  if exists (select 1 from public.document_debts where user_id = uid and status = 'open') then
    return jsonb_build_object('ok', false, 'message', 'Un document perdu ou abîmé reste à régler avec la médiathèque. Une fois réglé, tu pourras supprimer ton compte.');
  end if;

  -- Réservations pas encore retirées : annulées (le livre n'est plus mis de
  -- côté pour personne). Les réservations retirées et les emprunts rendus
  -- restent, sans nom, pour les statistiques de prêt (voir anonymisation).
  delete from public.reservations where user_id = uid and status in ('panier', 'preparation', 'pret');

  -- Toutes les colonnes qui pointent vers le compte sans « on delete cascade » :
  -- mises à null (ou lignes supprimées si la colonne est obligatoire).
  for fk in
    select c.conrelid::regclass as tbl, a.attname as col, a.attnotnull as notnull
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f'
      and c.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass)
      and c.confdeltype <> 'c'
      and array_length(c.conkey, 1) = 1
      and c.conrelid::regclass::text not like 'auth.%'
  loop
    if fk.notnull then
      execute format('delete from %s where %I = $1', fk.tbl, fk.col) using uid;
    else
      execute format('update %s set %I = null where %I = $1', fk.tbl, fk.col, fk.col) using uid;
    end if;
  end loop;

  delete from public.profiles where id = uid;
  delete from auth.users where id = uid;

  return jsonb_build_object('ok', true, 'message', 'Ton compte a été supprimé.');
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- =====================================================================
-- 3. Supprimer seulement son accès à l'appli
-- =====================================================================
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

-- =====================================================================
-- 4. Plus de grands tirets dans les messages de la base
-- =====================================================================
-- Plus aucun grand tiret dans les messages envoyés par la base (23/10/2026) :
-- notifications de défis réussis, messages d'erreur de réservation, etc.
-- Les fonctions concernées sont réécrites à l'identique, avec « - » à la place
-- de « — » entouré d'espaces (les tirets collés, ex. dans une expression
-- régulière, ne sont pas touchés).

do $$
declare
  f record;
  def text;
begin
  for f in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.prosrc like '% — %'
  loop
    def := pg_get_functiondef(f.oid);
    execute replace(def, ' — ', ' - ');
  end loop;
end $$;

-- Notifications déjà reçues par les usagers.
update public.notifications set message = replace(message, ' — ', ' - ') where message like '% — %';

-- Vérification : doit renvoyer 0 et 0.
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosrc like '% — %') as fonctions_restantes,
  (select count(*) from public.notifications where message like '% — %') as notifications_restantes;

