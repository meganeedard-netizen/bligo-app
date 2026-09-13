-- Système de notifications réelles (réservation prête, rappel 24h, remerciement de don)
-- + les 10 paliers de fidélité BliGO + le badge spécial "Plume Locale".

-- 1. Table des notifications
create table public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.notifications enable row level security;

create policy "Un usager voit ses propres notifications"
  on public.notifications for select
  using (auth.uid() = user_id);

create policy "Un usager marque ses notifications comme lues"
  on public.notifications for update
  using (auth.uid() = user_id);

-- 2. Notification quand une réservation devient "prête à récupérer"
create or replace function public.notify_on_ready()
returns trigger
language plpgsql
security definer
as $$
declare
  v_title text;
begin
  if new.status = 'pret' and old.status is distinct from 'pret' then
    select title into v_title from public.books where id = new.book_id;
    insert into public.notifications (user_id, message)
    values (new.user_id, 'Votre réservation « ' || coalesce(v_title, '') || ' » est prête à récupérer à la médiathèque !');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_ready on public.reservations;
create trigger trg_notify_on_ready
  after update on public.reservations
  for each row execute procedure public.notify_on_ready();

-- 3. Rappel 24h avant remise en rayon (ajouté à la vérification déjà planifiée toutes les 15 min)
alter table public.reservations add column if not exists notified_24h boolean not null default false;

create or replace function public.expire_old_reservations()
returns void
language plpgsql
security definer
as $$
declare
  cutoff_48h timestamptz := now() - interval '48 hours';
  cutoff_24h timestamptz := now() - interval '24 hours';
begin
  insert into public.notifications (user_id, message)
  select r.user_id, 'Il vous reste 24h pour récupérer « ' || b.title || ' » avant qu''il ne reparte en rayon.'
  from public.reservations r
  join public.books b on b.id = r.book_id
  where r.status in ('preparation', 'pret')
    and r.created_at <= cutoff_24h
    and r.notified_24h = false;

  update public.reservations
  set notified_24h = true
  where status in ('preparation', 'pret') and created_at <= cutoff_24h and notified_24h = false;

  update public.books
  set available = true
  where id in (
    select book_id from public.reservations
    where status in ('preparation', 'pret') and created_at < cutoff_48h
  );

  update public.reservations
  set status = 'expiree'
  where status in ('preparation', 'pret') and created_at < cutoff_48h;
end;
$$;

-- 4. Vrai don (Bibliothèque Libre) : colonnes nécessaires
alter table public.free_books add column if not exists donated_by uuid references auth.users(id);
alter table public.free_books add column if not exists is_local_author boolean not null default false;
alter table public.books add column if not exists is_local_author boolean not null default false;

update public.books set is_local_author = true where category = 'Littérature antillaise';

drop policy if exists "Un usager peut proposer un don" on public.free_books;
create policy "Un usager peut proposer un don"
  on public.free_books for insert
  with check (auth.uid() = donated_by);

-- 5. Les 10 paliers de fidélité BliGO + le badge spécial "Plume Locale"
alter table public.profiles add column if not exists badge_tier integer not null default 0;
alter table public.profiles add column if not exists plume_locale_unlocked boolean not null default false;

create or replace function public.check_and_award_badges(p_user_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_total_exchanges int;
  v_local_count int;
  v_current_tier int;
  v_plume_unlocked boolean;
  r record;
begin
  select count(*) into v_total_exchanges
  from public.free_books
  where donated_by = p_user_id or borrowed_by = p_user_id;

  select count(*) into v_local_count
  from public.free_books
  where (donated_by = p_user_id or borrowed_by = p_user_id) and is_local_author = true;

  select badge_tier, plume_locale_unlocked into v_current_tier, v_plume_unlocked
  from public.profiles where id = p_user_id;

  for r in
    select * from (values
      (1, 1, '📖 Félicitations ! Vous venez de débloquer le badge Premier Chapitre. Votre aventure BliGO commence aujourd''hui !'),
      (2, 3, '🔍 Bravo ! Badge Petit Curieux débloqué. Votre passion pour la lecture commence à porter ses fruits dans le quartier !'),
      (3, 5, '🎯 Bien joué ! Vous avez débloqué le badge Dénicheur. Trouver les plus belles pépites de la commune, c''est votre spécialité !'),
      (4, 10, '📚 Super ! Badge Bouquineur débloqué. Déjà 10 livres remis en circulation grâce à vous. Merci pour la communauté !'),
      (5, 25, '🤝 Impressionnant ! Vous obtenez le badge Passeur de Mots. Votre générosité fait voyager la culture de voisin en voisin !'),
      (6, 50, '🚀 Quel rythme ! Félicitations, vous avez débloqué le badge Dévoreur. Plus rien n''arrête votre soif de lecture !'),
      (7, 75, '🌟 Chapeau bas ! Le badge Bibliophile est à vous. Un véritable pilier de la lecture partagée au cœur de votre commune !'),
      (8, 100, '🏰 Incroyable ! Vous décrochez le badge Gardien du Savoir. 100 livres partagés, un immense merci pour ce formidable impact local !'),
      (9, 150, '👑 Légendaire ! Badge Maître des Pages débloqué. Votre engagement inspire toute la communauté BliGO !'),
      (10, 250, '🏆 Sommet atteint ! Bravo, vous êtes officiellement une Légende BliGO. La culture de votre commune vous dit un grand MERCI !')
    ) as t(tier, threshold, message)
    where tier > coalesce(v_current_tier, 0) and v_total_exchanges >= threshold
    order by tier asc
  loop
    insert into public.notifications (user_id, message) values (p_user_id, r.message);
    update public.profiles set badge_tier = r.tier where id = p_user_id;
  end loop;

  if v_local_count >= 3 and not coalesce(v_plume_unlocked, false) then
    insert into public.notifications (user_id, message)
    values (p_user_id, '🌴 Bravo péyi ! Vous avez débloqué le badge Plume Locale. Merci de faire rayonner les auteurs et la culture du territoire !');
    update public.profiles set plume_locale_unlocked = true where id = p_user_id;
  end if;
end;
$$;

-- 6. Points + notification de remerciement + vérification des badges à chaque don
create or replace function public.award_points_on_donation()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.donated_by is not null then
    update public.profiles set loyalty_points = loyalty_points + 10 where id = new.donated_by;
    insert into public.notifications (user_id, message)
    values (new.donated_by, 'Merci pour votre contribution culturelle ! Vous gagnez 10 points de fidélité.');
    perform public.check_and_award_badges(new.donated_by);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_award_points_on_donation on public.free_books;
create trigger trg_award_points_on_donation
  after insert on public.free_books
  for each row execute procedure public.award_points_on_donation();

-- 7. Points + vérification des badges à chaque emprunt en Bibliothèque Libre
create or replace function public.borrow_free_book(p_book_id bigint)
returns boolean
language plpgsql
security definer
as $$
declare
  affected int;
begin
  update public.free_books
  set available = false, borrowed_by = auth.uid()
  where id = p_book_id and available = true;
  get diagnostics affected = row_count;
  if affected > 0 then
    update public.profiles set loyalty_points = loyalty_points + 5 where id = auth.uid();
    perform public.check_and_award_badges(auth.uid());
  end if;
  return affected > 0;
end;
$$;
