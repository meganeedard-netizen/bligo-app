-- BliGO : sessions de don (13/11/2026)
-- ============================================================
-- Avant : l'agent scannait la carte du donateur puis cataloguait, et chaque
-- livre catalogué donnait 10 points tout de suite. On ne savait pas combien
-- de documents avaient été apportés ni combien avaient été écartés. Le badge
-- Cœur Généreux et le défi Vide-Bibliothèque ne comptaient que l'ancienne
-- Bibliothèque libre (free_books) : les dons faits au comptoir ne comptaient pas.
--
-- Maintenant :
-- 1. Une session de don est enregistrée (donateur avec compte, ou anonyme).
-- 2. Chaque document catalogué pendant la session = gardé (avec son nombre
--    d'exemplaires). Le bouton « Non retenu » compte les écartés.
-- 3. À la fin, l'agent confirme le nombre de documents apportés et ce que
--    deviennent les non retenus. Le donateur reçoit alors UNE notification
--    + un e-mail : « Merci pour ton don, ta Médiathèque Municipale a gardé
--    X documents, tu reçois Y points » (+ badge débloqué s'il y en a un).
-- 4. Badge Cœur Généreux (5 documents gardés au total) et défi
--    Vide-Bibliothèque (3 documents gardés dans l'année) comptent enfin ces dons.
-- 5. Une session oubliée ouverte est fermée toute seule après 12 h.
--
-- Ré-exécutable. À exécuter dans Supabase : SQL Editor > New query > Run.

-- ---------- 1. Tables ----------
create table if not exists public.donation_sessions (
  id bigint generated always as identity primary key,
  commune_id bigint not null references public.communes(id) on delete cascade,
  donor_id uuid references auth.users(id) on delete set null,
  donor_label text,
  agent_id uuid references auth.users(id) on delete set null,
  started_at timestamptz not null default now(),
  closed_at timestamptz,
  received_count integer,
  retained_count integer not null default 0,
  rejected_count integer not null default 0,
  rejected_destination text check (rejected_destination in ('rendu', 'don', 'vente', 'recyclage', 'autre')),
  points_awarded integer not null default 0
);

create index if not exists donation_sessions_commune_idx on public.donation_sessions (commune_id, started_at);
create index if not exists donation_sessions_open_idx on public.donation_sessions (agent_id) where closed_at is null;

alter table public.donation_sessions enable row level security;

drop policy if exists "Les agents voient les dons de leur médiathèque" on public.donation_sessions;
create policy "Les agents voient les dons de leur médiathèque"
  on public.donation_sessions for select
  using (public.is_super_admin() or (public.is_agent() and commune_id = public.agent_commune_id()));

drop policy if exists "Un usager voit ses dons" on public.donation_sessions;
create policy "Un usager voit ses dons"
  on public.donation_sessions for select
  using (donor_id = auth.uid());
-- Aucune policy d'écriture : tout passe par les fonctions ci-dessous.

alter table public.donations add column if not exists session_id bigint references public.donation_sessions(id) on delete set null;
alter table public.donations add column if not exists copies integer not null default 1;

drop policy if exists "Un usager voit ses dons de livres" on public.donations;
create policy "Un usager voit ses dons de livres"
  on public.donations for select
  using (donor_id = auth.uid());

-- Type de notification : l'appli ouvre une fenêtre de remerciement pour 'don'.
alter table public.notifications add column if not exists kind text;
alter table public.notifications add column if not exists data jsonb;

-- ---------- 2. Ouvrir une session ----------
create or replace function public.donation_session_start(p_donor_id uuid default null, p_donor_label text default null)
returns public.donation_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commune bigint := public.agent_commune_id();
  v_row public.donation_sessions;
  r record;
begin
  if not public.is_agent() or v_commune is null then
    raise exception 'Réservé aux agents de la médiathèque';
  end if;
  if exists (select 1 from public.communes c where c.id = v_commune and not c.donations_enabled) then
    raise exception 'Cette médiathèque n''accepte pas les dons de livres pour le moment. La direction peut les activer dans Réglages.';
  end if;

  -- Une seule session ouverte par agent : la précédente est clôturée telle quelle.
  for r in select id from public.donation_sessions where agent_id = auth.uid() and closed_at is null loop
    perform public._donation_session_close(r.id, null, null);
  end loop;

  insert into public.donation_sessions (commune_id, donor_id, donor_label, agent_id)
  values (v_commune, p_donor_id, case when p_donor_id is null then coalesce(nullif(trim(p_donor_label), ''), 'Don anonyme') end, auth.uid())
  returning * into v_row;
  return v_row;
end;
$$;

-- Session encore ouverte de l'agent (logiciel rechargé en cours de don).
create or replace function public.donation_session_current()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select to_jsonb(s) || jsonb_build_object('donor_name', coalesce(p.full_name, s.donor_label))
    from public.donation_sessions s
    left join public.profiles p on p.id = s.donor_id
   where s.agent_id = auth.uid() and s.closed_at is null
   order by s.started_at desc
   limit 1;
$$;

-- ---------- 3. Pendant la session ----------
create or replace function public.donation_add_retained(p_session_id bigint, p_book_id bigint, p_copies integer default 1)
returns public.donation_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_s public.donation_sessions;
  v_n integer := greatest(coalesce(p_copies, 1), 1);
begin
  select * into v_s from public.donation_sessions where id = p_session_id for update;
  if v_s.id is null or v_s.closed_at is not null then raise exception 'Session de don terminée'; end if;
  if not (public.is_super_admin() or (public.is_agent() and v_s.commune_id = public.agent_commune_id())) then
    raise exception 'Non autorisé';
  end if;

  insert into public.donations (donor_id, book_id, title, author, points_awarded, session_id, copies)
  select v_s.donor_id, b.id, coalesce(b.title, 'Titre inconnu'), coalesce(b.author, 'Auteur inconnu'), 0, v_s.id, v_n
    from public.books b where b.id = p_book_id;

  update public.donation_sessions set retained_count = retained_count + v_n
   where id = v_s.id returning * into v_s;
  return v_s;
end;
$$;

create or replace function public.donation_add_rejected(p_session_id bigint, p_delta integer default 1)
returns public.donation_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_s public.donation_sessions;
begin
  select * into v_s from public.donation_sessions where id = p_session_id for update;
  if v_s.id is null or v_s.closed_at is not null then raise exception 'Session de don terminée'; end if;
  if not (public.is_super_admin() or (public.is_agent() and v_s.commune_id = public.agent_commune_id())) then
    raise exception 'Non autorisé';
  end if;
  update public.donation_sessions set rejected_count = greatest(rejected_count + coalesce(p_delta, 1), 0)
   where id = v_s.id returning * into v_s;
  return v_s;
end;
$$;

-- ---------- 4. Clôture : points, badge, défi, notification, e-mail ----------
create or replace function public._donation_session_close(p_session_id bigint, p_received integer, p_destination text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_s public.donation_sessions;
  v_received integer;
  v_points integer := 0;
  v_tier_before integer;
  v_tier_after integer;
  v_total_kept integer;
  v_year_kept integer;
  v_badges text[] := '{}';
  v_tiers text[] := array['Premier Chapitre', 'Petit Curieux', 'Dénicheur', 'Bouquineur', 'Passeur de Mots',
                          'Dévoreur', 'Bibliophile', 'Gardien du Savoir', 'Maître des Pages', 'Légende BliGO'];
  v_msg text;
  v_name text;
  v_email text;
  v_doc text;
  i integer;
begin
  select * into v_s from public.donation_sessions where id = p_session_id for update;
  if v_s.id is null then raise exception 'Session de don introuvable'; end if;
  if v_s.closed_at is not null then return to_jsonb(v_s); end if;

  v_received := greatest(coalesce(p_received, v_s.retained_count + v_s.rejected_count), v_s.retained_count);
  if v_s.donor_id is not null then v_points := v_s.retained_count * 10; end if;

  update public.donation_sessions
     set closed_at = now(),
         received_count = v_received,
         rejected_count = v_received - retained_count,
         rejected_destination = case when v_received > retained_count then p_destination end,
         points_awarded = v_points
   where id = v_s.id
  returning * into v_s;

  -- Rien à créditer : session vide ou donateur sans compte.
  if v_s.donor_id is null or v_received = 0 then
    return to_jsonb(v_s);
  end if;

  update public.donations set points_awarded = 10 * copies where session_id = v_s.id;

  select badge_tier, full_name into v_tier_before, v_name from public.profiles where id = v_s.donor_id;
  if v_points > 0 then
    update public.profiles set loyalty_points = coalesce(loyalty_points, 0) + v_points where id = v_s.donor_id;
  end if;

  -- Documents gardés au total (dons au comptoir + ancienne Bibliothèque libre).
  select coalesce(sum(d.copies), 0) into v_total_kept
    from public.donations d where d.donor_id = v_s.donor_id and d.points_awarded > 0;
  v_total_kept := v_total_kept + (select count(*) from public.free_books f where f.donated_by = v_s.donor_id);
  select coalesce(sum(d.copies), 0) into v_year_kept
    from public.donations d where d.donor_id = v_s.donor_id and d.points_awarded > 0
     and d.created_at >= now() - interval '1 year';

  if v_total_kept >= 5 and not exists (select 1 from public.profiles where id = v_s.donor_id and coeur_genereux_unlocked) then
    update public.profiles set coeur_genereux_unlocked = true where id = v_s.donor_id;
    insert into public.notifications (user_id, message)
    values (v_s.donor_id, '💛 Un grand Cœur ! Tu as débloqué le badge Cœur Généreux. Grâce à tes dons, tu donnes une seconde vie aux livres !');
    v_badges := array_append(v_badges, 'Cœur Généreux');
  end if;

  if v_year_kept >= 3 and not exists (select 1 from public.defis_completed where user_id = v_s.donor_id and defi_code = 'vide_bibliotheque') then
    insert into public.defis_completed (user_id, defi_code) values (v_s.donor_id, 'vide_bibliotheque');
    update public.profiles set loyalty_points = coalesce(loyalty_points, 0) + 100 where id = v_s.donor_id;
    insert into public.notifications (user_id, message)
    values (v_s.donor_id, '🎉 Défi « Vide-Bibliothèque » réussi ! 3 dons gardés dans l''année, tu gagnes 100 points de fidélité.');
    v_points := v_points + 100;
  end if;

  perform public.check_and_award_badges(v_s.donor_id);
  select badge_tier into v_tier_after from public.profiles where id = v_s.donor_id;
  if coalesce(v_tier_after, 0) > coalesce(v_tier_before, 0) then
    for i in (coalesce(v_tier_before, 0) + 1)..least(v_tier_after, 10) loop
      v_badges := array_append(v_badges, v_tiers[i]);
    end loop;
  end if;

  v_doc := case when v_s.retained_count > 1 then ' documents' else ' document' end;
  if v_s.retained_count > 0 then
    v_msg := '💛 Merci pour ton don ! Ta Médiathèque Municipale a gardé ' || v_s.retained_count || v_doc
          || case when v_received > v_s.retained_count then ' sur ' || v_received else '' end
          || ' pour son catalogue. Tu reçois ' || v_points || ' points de fidélité.'
          || case when array_length(v_badges, 1) = 1 then ' Et tu débloques le badge ' || v_badges[1] || ' !'
                  when array_length(v_badges, 1) > 1 then ' Et tu débloques les badges ' || array_to_string(v_badges, ', ') || ' !'
                  else '' end;
  else
    v_msg := '💛 Merci pour ton don ! Cette fois, ta Médiathèque Municipale n''a pas pu garder les documents apportés, mais merci beaucoup d''avoir pensé à elle.';
  end if;

  insert into public.notifications (user_id, message, kind, data)
  values (v_s.donor_id, v_msg, 'don', jsonb_build_object(
    'session_id', v_s.id, 'received', v_received, 'retained', v_s.retained_count,
    'points', v_points, 'badges', to_jsonb(v_badges)));

  select u.email into v_email from auth.users u where u.id = v_s.donor_id;
  if v_email is not null and to_regclass('public.email_outbox') is not null then
    insert into public.email_outbox (to_email, to_name, subject, body_text)
    values (v_email, v_name, 'Merci pour ton don !',
      'Bonjour ' || coalesce(v_name, '') || E',\n\n'
      || substr(v_msg, 3) || E'\n\n'
      || E'Retrouve tes points et tes badges dans l''appli BliGO.\n\nÀ bientôt,\nL''équipe BliGO');
  end if;

  return to_jsonb(v_s) || jsonb_build_object('badges', to_jsonb(v_badges), 'points_total', v_points);
end;
$$;

revoke all on function public._donation_session_close(bigint, integer, text) from public, anon, authenticated;

create or replace function public.donation_session_close(p_session_id bigint, p_received integer default null, p_destination text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commune bigint;
begin
  select commune_id into v_commune from public.donation_sessions where id = p_session_id;
  if not (public.is_super_admin() or (public.is_agent() and v_commune = public.agent_commune_id())) then
    raise exception 'Non autorisé';
  end if;
  return public._donation_session_close(p_session_id, p_received, p_destination);
end;
$$;

-- Sessions oubliées ouvertes : fermées au bout de 12 h (le donateur reçoit ses points).
create or replace function public.donation_sessions_autoclose()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare r record;
begin
  for r in select id from public.donation_sessions where closed_at is null and started_at < now() - interval '12 hours' loop
    perform public._donation_session_close(r.id, null, null);
  end loop;
end;
$$;

revoke all on function public.donation_sessions_autoclose() from public, anon, authenticated;

grant execute on function public.donation_session_start(uuid, text) to authenticated;
grant execute on function public.donation_session_current() to authenticated;
grant execute on function public.donation_add_retained(bigint, bigint, integer) to authenticated;
grant execute on function public.donation_add_rejected(bigint, integer) to authenticated;
grant execute on function public.donation_session_close(bigint, integer, text) to authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'donation-sessions-autoclose') then
    perform cron.unschedule('donation-sessions-autoclose');
  end if;
  perform cron.schedule('donation-sessions-autoclose', '17 * * * *', 'select public.donation_sessions_autoclose();');
end $$;
