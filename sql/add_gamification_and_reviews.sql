-- BliGO — Refonte gamification (XP) + avis de la communauté + défis + parrainage.
--
-- Change le système de paliers de fidélité : au lieu de compter les échanges
-- (dons + emprunts en Bibliothèque Libre), les 10 paliers se basent maintenant
-- sur le total de points de fidélité (XP) cumulés par l'usager, quelle que
-- soit l'action qui les a rapportés. Les messages de déblocage restent
-- identiques à ceux déjà en place.

-- ============================================================
-- 1. Nouvelles colonnes profils
-- ============================================================

-- Sous-compteur dédié aux actions sur des livres "Plume Locale" (auteur
-- local), qui débloque le badge spécial à 150 XP cumulés sur ce sous-compteur
-- uniquement (distinct du total XP général).
alter table public.profiles add column if not exists plume_locale_xp integer not null default 0;

-- Parrainage : le filleul renseigne le n° d'abonné de son parrain à
-- l'inscription (facultatif). Le parrain gagne +50 XP dès que le filleul est
-- validé (compte 'officiel' validé par un agent, ou compte 'libre' validé
-- automatiquement à la création).
alter table public.profiles add column if not exists referred_by uuid references auth.users(id);
alter table public.profiles add column if not exists referral_rewarded boolean not null default false;

-- ============================================================
-- 2. Inscription : prise en compte du code de parrainage
-- ============================================================
-- Le formulaire d'inscription envoie le n° d'abonné du parrain (s'il y en a
-- un) dans les métadonnées ; on le résout ici en uuid.
create or replace function public.handle_new_user()
returns trigger as $$
declare
  v_account_type text := case when new.raw_user_meta_data->>'account_type' = 'officiel' then 'officiel' else 'libre' end;
  v_commune_id bigint := nullif(new.raw_user_meta_data->>'commune_id', '')::bigint;
  v_referrer_id uuid;
begin
  select id into v_referrer_id
  from public.profiles
  where subscriber_number = nullif(new.raw_user_meta_data->>'referral_code', '');

  insert into public.profiles (id, full_name, subscriber_number, account_type, commune_id, registration_status, referred_by)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', 'Nouvel usager'),
    'VF-' || to_char(now(), 'YYYY') || '-' || lpad(floor(random() * 99999)::text, 5, '0'),
    v_account_type,
    case when v_account_type = 'officiel' then v_commune_id else null end,
    case when v_account_type = 'officiel' then 'pre_inscrit' else 'valide' end,
    v_referrer_id
  );
  return new;
end;
$$ language plpgsql security definer;

-- Récompense le parrain dès que le filleul passe (ou est créé) en statut
-- 'valide' — qu'il s'agisse d'une validation par un agent (compte officiel)
-- ou d'une validation automatique (compte libre, dès l'inscription).
create or replace function public.check_referral_reward()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.registration_status = 'valide' and new.referred_by is not null and not coalesce(new.referral_rewarded, false) then
    update public.profiles set loyalty_points = loyalty_points + 50 where id = new.referred_by;
    insert into public.notifications (user_id, message)
    values (new.referred_by, '🎉 Merci d''avoir parrainé un nouvel usager BliGO ! Vous gagnez 50 points de fidélité.');
    perform public.check_and_award_badges(new.referred_by);
    update public.profiles set referral_rewarded = true where id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_check_referral_reward_insert on public.profiles;
create trigger trg_check_referral_reward_insert
  after insert on public.profiles
  for each row execute procedure public.check_referral_reward();

drop trigger if exists trg_check_referral_reward_update on public.profiles;
create trigger trg_check_referral_reward_update
  after update on public.profiles
  for each row execute procedure public.check_referral_reward();

-- ============================================================
-- 3. Avis de la communauté (note + commentaire ≤ 300 caractères)
-- ============================================================
create table public.book_reviews (
  id bigint generated always as identity primary key,
  book_id bigint not null references public.books(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 300),
  created_at timestamptz not null default now(),
  unique (book_id, user_id)
);

alter table public.book_reviews enable row level security;

create policy "Les avis sont publics en lecture"
  on public.book_reviews for select
  using (true);

create policy "Un usager dépose son propre avis"
  on public.book_reviews for insert
  with check (auth.uid() = user_id);

create policy "Un usager modifie son propre avis"
  on public.book_reviews for update
  using (auth.uid() = user_id);

-- +15 XP au premier avis déposé sur un livre donné (la contrainte unique
-- garantit qu'un seul avis par livre et par usager peut exister — modifier
-- un avis existant ne redéclenche pas ce trigger, qui ne se déclenche qu'à
-- l'insertion). +20 XP de bonus si le livre est taggué "Plume Locale".
create or replace function public.award_points_on_review()
returns trigger
language plpgsql
security definer
as $$
declare
  v_is_local boolean;
  v_bonus integer := 0;
begin
  select is_local_author into v_is_local from public.books where id = new.book_id;
  if v_is_local then v_bonus := 20; end if;

  update public.profiles set loyalty_points = loyalty_points + 15 + v_bonus where id = new.user_id;
  if v_bonus > 0 then
    update public.profiles set plume_locale_xp = plume_locale_xp + v_bonus where id = new.user_id;
  end if;

  insert into public.notifications (user_id, message)
  values (new.user_id, 'Merci pour votre avis ! Vous gagnez ' || (15 + v_bonus) || ' points de fidélité' || (case when v_bonus > 0 then ' (dont 20 de bonus Plume Locale)' else '' end) || '.');

  perform public.check_and_award_badges(new.user_id);
  perform public.check_defis(new.user_id);
  return new;
end;
$$;

drop trigger if exists trg_award_points_on_review on public.book_reviews;
create trigger trg_award_points_on_review
  after insert on public.book_reviews
  for each row execute procedure public.award_points_on_review();

-- ============================================================
-- 4. Refonte des points sur dons / emprunts en Bibliothèque Libre
-- ============================================================
-- +30 XP pour le tout premier don OU emprunt (déclenche le badge Premier
-- Chapitre), +20 XP pour chaque don/emprunt suivant, +20 XP de bonus
-- additionnel si le livre est taggué "Plume Locale".
create or replace function public.award_points_on_donation()
returns trigger
language plpgsql
security definer
as $$
declare
  v_prior_count integer;
  v_base integer;
  v_bonus integer := 0;
begin
  if new.donated_by is not null then
    select count(*) into v_prior_count
    from public.free_books
    where (donated_by = new.donated_by or borrowed_by = new.donated_by) and id <> new.id;

    v_base := case when v_prior_count = 0 then 30 else 20 end;
    if new.is_local_author then v_bonus := 20; end if;

    update public.profiles set loyalty_points = loyalty_points + v_base + v_bonus where id = new.donated_by;
    if v_bonus > 0 then
      update public.profiles set plume_locale_xp = plume_locale_xp + v_bonus where id = new.donated_by;
    end if;

    insert into public.notifications (user_id, message)
    values (new.donated_by, 'Merci pour votre contribution culturelle ! Vous gagnez ' || (v_base + v_bonus) || ' points de fidélité.');
    perform public.check_and_award_badges(new.donated_by);
    perform public.check_defis(new.donated_by);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_award_points_on_donation on public.free_books;
create trigger trg_award_points_on_donation
  after insert on public.free_books
  for each row execute procedure public.award_points_on_donation();

create or replace function public.borrow_free_book(p_book_id bigint)
returns boolean
language plpgsql
security definer
as $$
declare
  affected integer;
  v_is_local boolean;
  v_prior_count integer;
  v_base integer;
  v_bonus integer := 0;
begin
  update public.free_books
  set available = false, borrowed_by = auth.uid()
  where id = p_book_id and available = true;
  get diagnostics affected = row_count;

  if affected > 0 then
    select is_local_author into v_is_local from public.free_books where id = p_book_id;

    select count(*) into v_prior_count
    from public.free_books
    where (donated_by = auth.uid() or borrowed_by = auth.uid()) and id <> p_book_id;

    v_base := case when v_prior_count = 0 then 30 else 20 end;
    if v_is_local then v_bonus := 20; end if;

    update public.profiles set loyalty_points = loyalty_points + v_base + v_bonus where id = auth.uid();
    if v_bonus > 0 then
      update public.profiles set plume_locale_xp = plume_locale_xp + v_bonus where id = auth.uid();
    end if;

    perform public.check_and_award_badges(auth.uid());
    perform public.check_defis(auth.uid());
  end if;
  return affected > 0;
end;
$$;

grant execute on function public.borrow_free_book(bigint) to authenticated;

-- ============================================================
-- 5. Paliers de fidélité : basés sur le total XP (plus le nombre d'échanges)
-- ============================================================
create or replace function public.check_and_award_badges(p_user_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_xp integer;
  v_plume_xp integer;
  v_current_tier integer;
  v_plume_unlocked boolean;
  r record;
begin
  select loyalty_points, plume_locale_xp, badge_tier, plume_locale_unlocked
    into v_xp, v_plume_xp, v_current_tier, v_plume_unlocked
    from public.profiles where id = p_user_id;

  for r in
    select * from (values
      (1, 30, '📖 Félicitations ! Vous venez de débloquer le badge Premier Chapitre. Votre aventure BliGO commence aujourd''hui !'),
      (2, 100, '🔍 Bravo ! Badge Petit Curieux débloqué. Votre passion pour la lecture commence à porter ses fruits dans le quartier !'),
      (3, 250, '🎯 Bien joué ! Vous avez débloqué le badge Dénicheur. Trouver les plus belles pépites de la commune, c''est votre spécialité !'),
      (4, 500, '📚 Super ! Badge Bouquineur débloqué. Déjà 10 livres remis en circulation grâce à vous. Merci pour la communauté !'),
      (5, 1000, '🤝 Impressionnant ! Vous obtenez le badge Passeur de Mots. Votre générosité fait voyager la culture de voisin en voisin !'),
      (6, 2000, '🚀 Quel rythme ! Félicitations, vous avez débloqué le badge Dévoreur. Plus rien n''arrête votre soif de lecture !'),
      (7, 3500, '🌟 Chapeau bas ! Le badge Bibliophile est à vous. Un véritable pilier de la lecture partagée au cœur de votre commune !'),
      (8, 5000, '🏰 Incroyable ! Vous décrochez le badge Gardien du Savoir. 100 livres partagés, un immense merci pour ce formidable impact local !'),
      (9, 7500, '👑 Légendaire ! Badge Maître des Pages débloqué. Votre engagement inspire toute la communauté BliGO !'),
      (10, 10000, '🏆 Sommet atteint ! Bravo, vous êtes officiellement une Légende BliGO. La culture de votre commune vous dit un grand MERCI !')
    ) as t(tier, threshold, message)
    where tier > coalesce(v_current_tier, 0) and v_xp >= threshold
    order by tier asc
  loop
    insert into public.notifications (user_id, message) values (p_user_id, r.message);
    update public.profiles set badge_tier = r.tier where id = p_user_id;
  end loop;

  if coalesce(v_plume_xp, 0) >= 150 and not coalesce(v_plume_unlocked, false) then
    insert into public.notifications (user_id, message)
    values (p_user_id, '🌴 Bravo péyi ! Vous avez débloqué le badge Plume Locale. Merci de faire rayonner les auteurs et la culture du territoire !');
    update public.profiles set plume_locale_unlocked = true where id = p_user_id;
  end if;
end;
$$;

-- ============================================================
-- 6. Défis (missions)
-- ============================================================
create table public.defis_completed (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  defi_code text not null check (defi_code in ('vide_bibliotheque', 'critique_litteraire', 'evenement_culturel', 'marathon_10_livres')),
  completed_at timestamptz not null default now(),
  unique (user_id, defi_code)
);

alter table public.defis_completed enable row level security;

create policy "Un usager voit ses défis complétés"
  on public.defis_completed for select
  using (auth.uid() = user_id);

create or replace function public.check_defis(p_user_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_donations_30d integer;
  v_reviews_count integer;
  v_read_count integer;
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
end;
$$;

-- Marathon 10 Livres se base sur les réservations Click & Collect récupérées :
-- il faut donc aussi vérifier les défis à chaque retrait.
create or replace function public.award_points_on_pickup()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.status = 'recupere' and old.status is distinct from 'recupere' then
    update public.profiles set loyalty_points = loyalty_points + 10 where id = new.user_id;
    perform public.check_and_award_badges(new.user_id);
    perform public.check_defis(new.user_id);
  end if;
  return new;
end;
$$;

-- ============================================================
-- 7. Défi "Événement Culturel" : présence enregistrée par un agent
-- ============================================================
create table public.event_checkins (
  id bigint generated always as identity primary key,
  event_id bigint not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  checked_in_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (event_id, user_id)
);

alter table public.event_checkins enable row level security;

create policy "Un usager voit ses présences enregistrées"
  on public.event_checkins for select
  using (auth.uid() = user_id);

create or replace function public.record_event_checkin(p_user_id uuid, p_event_id bigint)
returns boolean
language plpgsql
security definer
as $$
declare
  v_event_title text;
  v_already boolean;
begin
  if not public.is_agent() then
    raise exception 'Seul un agent peut enregistrer une présence.';
  end if;

  select exists(select 1 from public.event_checkins where event_id = p_event_id and user_id = p_user_id) into v_already;
  if v_already then
    return false;
  end if;

  insert into public.event_checkins (event_id, user_id, checked_in_by) values (p_event_id, p_user_id, auth.uid());
  select title into v_event_title from public.events where id = p_event_id;

  if not exists (select 1 from public.defis_completed where user_id = p_user_id and defi_code = 'evenement_culturel') then
    insert into public.defis_completed (user_id, defi_code) values (p_user_id, 'evenement_culturel');
    update public.profiles set loyalty_points = loyalty_points + 80 where id = p_user_id;
    insert into public.notifications (user_id, message)
    values (p_user_id, '🎉 Défi « Événement Culturel » réussi ! Présence enregistrée à « ' || coalesce(v_event_title, '') || ' » — vous gagnez 80 points de fidélité.');
    perform public.check_and_award_badges(p_user_id);
  else
    insert into public.notifications (user_id, message)
    values (p_user_id, 'Présence enregistrée à « ' || coalesce(v_event_title, '') || ' ». Merci d''être venu(e) !');
  end if;

  return true;
end;
$$;

grant execute on function public.record_event_checkin(uuid, bigint) to authenticated;

-- ============================================================
-- 8. Recalcul immédiat des badges déjà en cours (nouveaux seuils XP)
-- ============================================================
do $$
declare r record;
begin
  for r in select id from public.profiles loop
    perform public.check_and_award_badges(r.id);
  end loop;
end $$;
