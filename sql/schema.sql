-- BliGO — schéma de base de données (Médiathèque de Val-Fleuri, commune pilote)
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

-- 1. Profils usagers (complète auth.users géré par Supabase Auth)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  subscriber_number text unique not null,
  account_type text not null default 'flash' check (account_type in ('officiel', 'flash')),
  loyalty_points integer not null default 0,
  reading_goal integer not null default 12,
  badge_tier integer not null default 0,
  plume_locale_unlocked boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Un usager voit son propre profil"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Un usager modifie son propre profil"
  on public.profiles for update
  using (auth.uid() = id);

-- Crée automatiquement un profil + numéro d'abonné à l'inscription
create function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, subscriber_number)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', 'Nouvel usager'),
    'VF-' || to_char(now(), 'YYYY') || '-' || lpad(floor(random() * 99999)::text, 5, '0')
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2. Catalogue de livres
create table public.books (
  id bigint generated always as identity primary key,
  title text not null,
  author text not null,
  cover_initial text not null default '',
  available boolean not null default true,
  category text check (
    category is null or category in (
      'Roman', 'Thriller', 'Science-Fiction', 'Jeunesse', 'BD & Mangas',
      'Bien-être', 'Maison', 'Histoire', 'Culture', 'Autres'
    )
  ),
  summary text,
  cover_url text,
  is_featured boolean not null default false,
  is_local_author boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.books enable row level security;

create policy "Le catalogue est public en lecture"
  on public.books for select
  using (true);

insert into public.books (title, author, cover_initial, available, category, summary, cover_url) values
  ('Texaco', 'Patrick Chamoiseau', 'T', true, 'Roman', 'Fresque d''un quartier populaire de Martinique à travers plusieurs générations d''une famille créole, de la période coloniale à l''urbanisation moderne. Prix Goncourt 1992.', 'img/covers/texaco.jpg'),
  ('Pluie et vent sur Télumée Miracle', 'Simone Schwarz-Bart', 'P', false, 'Roman', 'La vie de Télumée, une femme guadeloupéenne confrontée à l''amour, aux épreuves et à la résilience à travers les générations. Un texte fondateur de la littérature caribéenne.', 'img/covers/pluie-et-vent-sur-telumee-miracle.jpg'),
  ('Une si longue lettre', 'Mariama Bâ', 'U', true, 'Roman', 'Une veuve sénégalaise écrit une longue lettre à sa meilleure amie, méditant sur le mariage, la polygamie et la condition des femmes dans l''Afrique post-coloniale.', 'img/covers/une-si-longue-lettre.jpg'),
  ('Cahier d''un retour au pays natal', 'Aimé Césaire', 'C', false, 'Roman', 'Long poème fondateur du mouvement de la Négritude, méditation lyrique sur l''identité, la colonisation et l''héritage martiniquais et africain.', 'img/covers/cahier-dun-retour-au-pays-natal.jpg'),
  ('Ti Jean L''horizon', 'Simone Schwarz-Bart', 'T', true, 'Roman', 'Un conte initiatique et fantastique suivant Ti Jean dans une quête mêlant folklore caribéen, magie et recherche d''identité.', 'img/covers/ti-jean-lhorizon.jpg'),
  ('Les Soleils des indépendances', 'Ahmadou Kourouma', 'S', true, 'Roman', 'Portrait satirique d''un prince africain déchu, confronté aux désillusions des jeunes nations africaines nouvellement indépendantes.', 'img/covers/les-soleils-des-independances.jpg'),
  ('L''Étranger', 'Albert Camus', 'É', true, 'Roman', 'Meursault, employé indifférent à Alger, commet un acte de violence absurde et affronte l''exigence de sens de la société. Un classique de la littérature existentialiste.', 'img/covers/letranger.jpg'),
  ('La Saison de l''ombre', 'Léonora Miano', 'L', false, 'Roman', 'Un village africain confronté à la disparition de ses jeunes hommes à l''aube de la traite négrière transatlantique. Prix Goncourt des lycéens 2013.', 'img/covers/la-saison-de-lombre.jpg'),
  ('Le dîner. Une aventure dont vous êtes le héros', 'Freida McFadden', 'D', true, 'Thriller', 'Un dîner qui tourne au cauchemar : secrets, manipulation et tension psychologique dans ce thriller à l''intrigue redoutable.', 'img/covers/le-diner.jpg'),
  ('La prof', 'Freida McFadden', 'P', false, 'Thriller', 'Un thriller psychologique haletant autour d''une professeure dont le passé cache de sombres secrets, jusqu''au twist final.', 'img/covers/la-prof.jpg'),
  ('Les heures fragiles', 'Virginie Grimaldi', 'H', true, 'Roman', 'Un roman chaleureux et plein de vie sur des destins ordinaires qui se croisent à des moments fragiles, entre résilience et lien humain.', 'img/covers/les-heures-fragiles.jpg'),
  ('Tata', 'Valérie Perrin', 'T', true, 'Roman', 'Une saga familiale tendre et bouleversante explorant les secrets et les liens entre plusieurs générations de femmes.', 'img/covers/tata.jpg'),
  ('La psy', 'Freida McFadden', 'P', false, 'Thriller', 'Les séances d''une psychothérapeute basculent dans une toile de manipulation et de danger, dans ce thriller psychologique addictif.', 'img/covers/la-psy.jpg'),
  ('Quelqu''un d''autre', 'Guillaume Musso', 'Q', true, 'Thriller', 'Un thriller sur l''identité et les vies qu''on aurait pu vivre, avec les retournements de situation caractéristiques de Guillaume Musso.', 'img/covers/quelquun-dautre.jpg'),
  ('La femme de ménage', 'Freida McFadden', 'F', false, 'Thriller', 'Une femme sans domicile devient gouvernante dans une famille aisée, et se retrouve prise dans un engrenage de mensonges et de danger.', 'img/covers/femme-de-menage.jpg'),
  ('Celle qui sait', 'Riley Sager', 'C', true, 'Thriller', 'Un thriller à suspense où le passé trouble d''une femme refait surface, l''obligeant à affronter des secrets qu''elle croyait enterrés.', 'img/covers/celle-qui-sait.jpg'),
  ('La femme de ménage voit tout', 'Freida McFadden', 'F', true, 'Thriller', 'La suite de « La femme de ménage » : la nouvelle vie de Millie se fissure quand d''anciens secrets et de nouvelles menaces se percutent.', 'img/covers/femme-de-menage-voit-tout.jpg'),
  ('Les secrets de la femme de ménage', 'Freida McFadden', 'S', false, 'Thriller', 'La saga continue : Millie affronte un nouveau danger tandis que des vérités enfouies menacent la paix fragile qu''elle a construite.', 'img/covers/les-secrets-de-la-femme-de-menage.jpg'),
  ('D''autres printemps', 'Virginie Grimaldi', 'D', true, 'Roman', 'Un roman tout en tendresse sur les seconds départs et les liens familiaux qui se réinventent avec le temps.', 'img/covers/dautres-printemps.jpg'),
  ('L''homme qui lisait des livres', 'Rachid Benzine', 'H', true, 'Roman', 'Le portrait d''un homme pour qui la lecture est un refuge et une manière de comprendre le monde, entre transmission et émotion.', 'img/covers/lhomme-qui-lisait-des-livres.jpg'),
  ('L''invitée surprise', 'Alison Espach', 'I', false, 'Roman', 'Une comédie dramatique pleine de charme sur les secrets de famille qui refont surface le temps d''une réunion inattendue.', 'img/covers/linvitee-surprise.jpg'),
  ('La Petite bonne', 'Bérénice Pichat', 'P', true, 'Roman', 'Le récit sensible d''une jeune femme confrontée à la dureté du travail domestique et à la quête de sa propre place.', 'img/covers/la-petite-bonne.jpg'),
  ('La Porteuse de lettres', 'Francesca Giannone', 'P', true, 'Roman', 'Dans l''Italie du sud du XXe siècle, une factrice bouscule les traditions d''un village et devient une figure d''émancipation.', 'img/covers/la-porteuse-de-lettres.jpg'),
  ('Le Barman du Ritz', 'Philippe Collin', 'B', false, 'Roman', 'Paris, l''Occupation : le destin d''un barman du prestigieux hôtel Ritz, témoin discret d''une époque trouble.', 'img/covers/le-barman-du-ritz.jpg'),
  ('Les Habitantes', 'Pauline Peyrade', 'H', true, 'Roman', 'Un texte intense sur la vie de plusieurs femmes dans un même immeuble, entre solitude et sororité.', 'img/covers/les-habitantes.jpg'),
  ('Les Monsieur Madame visitent Fort Boyard', 'Roger Hargreaves', 'M', true, 'Jeunesse', 'Les personnages cultes de Monsieur Madame partent à l''aventure sur le célèbre fort, pour les plus jeunes lecteurs.', 'img/covers/monsieur-madame-fort-boyard.jpg'),
  ('Les saules', 'Mathilde Beaussault', 'S', false, 'Roman', 'Un roman à l''atmosphère envoûtante, entre nature, mémoire et secrets de famille.', 'img/covers/les-saules.jpg'),
  ('Mortelle Adèle Tome 23 - Nazebrocadabra !', 'Mr Tan & Diane Le Feyer', 'M', true, 'Jeunesse', 'Nouvelle aventure déjantée d''Adèle, l''héroïne préférée des jeunes lecteurs, toujours aussi grinçante et drôle.', 'img/covers/mortelle-adele-23.jpg'),
  ('Résister', 'Salomé Saqué', 'R', true, 'Autres', 'Un essai engagé sur les mobilisations citoyennes et politiques contemporaines, par la journaliste Salomé Saqué.', 'img/covers/resister.jpg'),
  ('Tout le monde aime Clara', 'David Foenkinos', 'T', false, 'Roman', 'Foenkinos signe un roman choral plein de finesse autour du destin de Clara, entre légèreté et profondeur.', 'img/covers/tout-le-monde-aime-clara.jpg'),
  ('Un avenir radieux', 'Pierre Lemaitre', 'U', true, 'Roman', 'Pierre Lemaitre déploie une fresque romanesque ambitieuse, entre satire sociale et sens du récit.', 'img/covers/un-avenir-radieux.jpg'),
  ('Un jour sans femme', 'Laetitia Colombani', 'U', true, 'Roman', 'Laetitia Colombani interroge la condition féminine à travers un récit poignant et engagé.', 'img/covers/un-jour-sans-femme.jpg'),
  ('Une unique lueur', 'Fred Vargas', 'U', false, 'Thriller', 'Une nouvelle enquête du commissaire Adamsberg, portée par l''univers singulier et atmosphérique de Fred Vargas.', 'img/covers/une-unique-lueur.jpg');

update public.books set is_featured = true where title = 'Texaco';
update public.books set is_local_author = true where title in ('Texaco', 'Pluie et vent sur Télumée Miracle', 'Cahier d''un retour au pays natal', 'Ti Jean L''horizon');

-- 3. Réservations Click & Collect
create table public.reservations (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id bigint not null references public.books(id) on delete cascade,
  status text not null default 'preparation' check (status in ('preparation', 'pret', 'recupere', 'expiree')),
  notified_24h boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.reservations enable row level security;

create policy "Un usager voit ses propres réservations"
  on public.reservations for select
  using (auth.uid() = user_id);

create policy "Un usager crée ses propres réservations"
  on public.reservations for insert
  with check (auth.uid() = user_id);

create policy "Un usager met à jour ses propres réservations"
  on public.reservations for update
  using (auth.uid() = user_id);

-- Retirer un livre de sa sélection tant qu'il est encore "en préparation" —
-- impossible une fois passé à "prêt" ou au-delà.
create policy "Un usager annule sa réservation tant qu'elle est en préparation"
  on public.reservations for delete
  using (auth.uid() = user_id and status = 'preparation');

-- Expiration automatique des réservations non récupérées sous 48h :
-- remet le livre en rayon et marque la réservation comme expirée.
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

-- Notification quand une réservation devient "prête à récupérer"
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

create extension if not exists pg_cron with schema extensions;

-- Notifications (réservation prête, rappel 24h, remerciement de don)
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

select cron.schedule('expire-reservations', '*/15 * * * *', $$select public.expire_old_reservations();$$);

-- Liste d'envie : les usagers peuvent marquer des livres d'intérêt, y compris
-- ceux actuellement indisponibles à la médiathèque.
create table public.wishlist (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id bigint not null references public.books(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, book_id)
);

alter table public.wishlist enable row level security;

create policy "Un usager voit sa propre liste d'envie"
  on public.wishlist for select
  using (auth.uid() = user_id);

create policy "Un usager ajoute à sa propre liste d'envie"
  on public.wishlist for insert
  with check (auth.uid() = user_id);

create policy "Un usager retire de sa propre liste d'envie"
  on public.wishlist for delete
  using (auth.uid() = user_id);

-- 4. Communes (fondation multi-communes)
create table public.communes (
  id bigint generated always as identity primary key,
  name text not null unique,
  timezone text not null default 'America/Guadeloupe',
  opening_hours text not null default '',
  created_at timestamptz not null default now()
);

alter table public.communes enable row level security;

create policy "Les communes sont publiques en lecture"
  on public.communes for select
  using (true);

insert into public.communes (name, timezone, opening_hours) values
  ('Val-Fleuri', 'America/Guadeloupe', 'Mardi-Vendredi 10h-18h · Samedi 10h-13h · Fermé dimanche et lundi'),
  ('Le Moule', 'America/Guadeloupe', 'Mardi-Samedi 9h-17h30 · Fermé dimanche et lundi'),
  ('Sainte-Anne', 'America/Guadeloupe', 'Mardi-Vendredi 9h30-17h · Samedi 9h30-12h30 · Fermé dimanche et lundi');

alter table public.books add column if not exists commune_id bigint references public.communes(id);
update public.books set commune_id = (select id from public.communes where name = 'Val-Fleuri') where commune_id is null;

-- 5. Bibliothèque Libre (dons, hors condition, cross-commune)
create table public.free_books (
  id bigint generated always as identity primary key,
  commune_id bigint not null references public.communes(id),
  title text not null,
  author text not null,
  cover_initial text not null default '',
  cover_url text,
  category text,
  summary text,
  available boolean not null default true,
  borrowed_by uuid references auth.users(id),
  borrowed_at timestamptz,
  donated_by uuid references auth.users(id),
  is_local_author boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.free_books enable row level security;

create policy "La Bibliothèque Libre est publique en lecture"
  on public.free_books for select
  using (true);

create policy "Un usager peut proposer un don"
  on public.free_books for insert
  with check (auth.uid() = donated_by);

-- Les 10 paliers de fidélité BliGO + le badge spécial "Plume Locale"
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

grant execute on function public.borrow_free_book(bigint) to authenticated;

-- Points automatiques pour chaque don proposé
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

-- 6. Points de fidélité automatiques
create or replace function public.award_points_on_pickup()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.status = 'recupere' and old.status is distinct from 'recupere' then
    update public.profiles set loyalty_points = loyalty_points + 10 where id = new.user_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_award_points_on_pickup on public.reservations;
create trigger trg_award_points_on_pickup
  after update on public.reservations
  for each row execute procedure public.award_points_on_pickup();

-- 7. Agenda culturel
create table public.events (
  id bigint generated always as identity primary key,
  commune_id bigint references public.communes(id),
  title text not null,
  description text,
  event_date timestamptz not null,
  location text,
  created_at timestamptz not null default now()
);

alter table public.events enable row level security;

create policy "Les événements sont publics en lecture"
  on public.events for select
  using (true);

create table public.event_rsvps (
  id bigint generated always as identity primary key,
  event_id bigint not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (event_id, user_id)
);

alter table public.event_rsvps enable row level security;

create policy "Les inscriptions sont publiques en lecture"
  on public.event_rsvps for select
  using (true);

create policy "Un usager s'inscrit lui-même"
  on public.event_rsvps for insert
  with check (auth.uid() = user_id);

create policy "Un usager se désinscrit lui-même"
  on public.event_rsvps for delete
  using (auth.uid() = user_id);

create or replace function public.award_points_on_rsvp()
returns trigger
language plpgsql
security definer
as $$
begin
  update public.profiles set loyalty_points = loyalty_points + 5 where id = new.user_id;
  return new;
end;
$$;

drop trigger if exists trg_award_points_on_rsvp on public.event_rsvps;
create trigger trg_award_points_on_rsvp
  after insert on public.event_rsvps
  for each row execute procedure public.award_points_on_rsvp();

insert into public.events (commune_id, title, description, event_date, location) values
  ((select id from public.communes where name = 'Val-Fleuri'), 'Club de lecture', 'Discussion autour de « Texaco » de Patrick Chamoiseau, animée par l''équipe de la médiathèque.', '2026-09-04 18:00:00+00', 'Médiathèque de Val-Fleuri'),
  ((select id from public.communes where name = 'Val-Fleuri'), 'Atelier d''écriture', 'Un atelier ouvert à tous pour découvrir l''écriture créole et créative.', '2026-09-11 17:00:00+00', 'Médiathèque de Val-Fleuri'),
  ((select id from public.communes where name = 'Le Moule'), 'Heure du conte', 'Séance de lecture pour les enfants de 4 à 8 ans.', '2026-09-06 10:30:00+00', 'Médiathèque du Moule');

-- 8. Pré-inscription : un compte créé est "pré-inscrit" et doit être validé par
-- un agent (vérification pièce d'identité + justificatif de domicile) avant que
-- sa carte / QR code ne soit active.
alter table public.profiles
  add column if not exists registration_status text not null default 'pre_inscrit'
    check (registration_status in ('pre_inscrit', 'valide'));

alter table public.profiles
  add column if not exists validated_at timestamptz;

alter table public.profiles
  add column if not exists validated_by uuid references auth.users(id);

create or replace function public.validate_registration(p_user_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  if not public.is_agent() then
    raise exception 'Seul un agent peut valider une inscription.';
  end if;

  update public.profiles
  set registration_status = 'valide',
      validated_at = now(),
      validated_by = auth.uid()
  where id = p_user_id;

  insert into public.notifications (user_id, message)
  values (p_user_id, 'Votre inscription a été validée par la médiathèque ! Votre carte et votre QR code sont maintenant actifs dans votre profil.');
end;
$$;

grant execute on function public.validate_registration(uuid) to authenticated;

-- 9. Types de compte : 'officiel' (rattaché à une commune, Click & Collect,
-- validation requise) ou 'libre' (pas de commune, Bibliothèque Libre
-- uniquement, validé automatiquement puisque sans condition de résidence).
alter table public.profiles drop constraint if exists profiles_account_type_check;
update public.profiles set account_type = 'libre' where account_type = 'flash';
alter table public.profiles add constraint profiles_account_type_check check (account_type in ('officiel', 'libre'));
alter table public.profiles alter column account_type set default 'libre';

alter table public.profiles add column if not exists commune_id bigint references public.communes(id);

create or replace function public.handle_new_user()
returns trigger as $$
declare
  v_account_type text := case when new.raw_user_meta_data->>'account_type' = 'officiel' then 'officiel' else 'libre' end;
  v_commune_id bigint := nullif(new.raw_user_meta_data->>'commune_id', '')::bigint;
begin
  insert into public.profiles (id, full_name, subscriber_number, account_type, commune_id, registration_status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', 'Nouvel usager'),
    'VF-' || to_char(now(), 'YYYY') || '-' || lpad(floor(random() * 99999)::text, 5, '0'),
    v_account_type,
    case when v_account_type = 'officiel' then v_commune_id else null end,
    case when v_account_type = 'officiel' then 'pre_inscrit' else 'valide' end
  );
  return new;
end;
$$ language plpgsql security definer;

create or replace function public.request_commune_attachment(p_commune_id bigint)
returns void
language plpgsql
security definer
as $$
begin
  update public.profiles
  set account_type = 'officiel',
      commune_id = p_commune_id,
      registration_status = 'pre_inscrit',
      validated_at = null,
      validated_by = null
  where id = auth.uid();
end;
$$;

grant execute on function public.request_commune_attachment(bigint) to authenticated;

-- 10. Préférences de lecture (posées à l'inscription) pour personnaliser les
-- recommandations affichées sur la page d'accueil.
alter table public.profiles add column if not exists preferred_categories text[] not null default '{}';
alter table public.profiles add column if not exists reading_pace integer;
alter table public.profiles add column if not exists onboarding_completed boolean not null default false;

-- 11. Refonte gamification (XP) + avis de la communauté + défis + parrainage.
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
  set available = false, borrowed_by = auth.uid(), borrowed_at = now()
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
  v_coeur_unlocked boolean;
  v_donation_count integer;
  r record;
begin
  select loyalty_points, plume_locale_xp, badge_tier, plume_locale_unlocked, coeur_genereux_unlocked
    into v_xp, v_plume_xp, v_current_tier, v_plume_unlocked, v_coeur_unlocked
    from public.profiles where id = p_user_id;

  for r in
    select * from (values
      (1, 30, '📖 Félicitations ! Tu viens de débloquer le badge Premier Chapitre. Ton aventure BliGO commence aujourd''hui !'),
      (2, 100, '🔍 Bravo ! Badge Petit Curieux débloqué. Ta passion pour la lecture commence à porter ses fruits dans le quartier !'),
      (3, 250, '🎯 Bien joué ! Tu as débloqué le badge Dénicheur. Trouver les plus belles pépites de la commune, c''est ta spécialité !'),
      (4, 500, '📚 Super ! Badge Bouquineur débloqué. Déjà 10 livres remis en circulation grâce à toi. Merci pour la communauté !'),
      (5, 1000, '🤝 Impressionnant ! Tu obtiens le badge Passeur de Mots. Ta générosité fait voyager la culture de voisin en voisin !'),
      (6, 2000, '🚀 Quel rythme ! Félicitations, tu as débloqué le badge Dévoreur. Plus rien n''arrête ta soif de lecture !'),
      (7, 3500, '🌟 Chapeau bas ! Le badge Bibliophile est à toi. Un véritable pilier de la lecture partagée au cœur de ta commune !'),
      (8, 5000, '🏰 Incroyable ! Tu décroches le badge Gardien du Savoir. 100 livres partagés, un immense merci pour ce formidable impact local !'),
      (9, 7500, '👑 Légendaire ! Badge Maître des Pages débloqué. Ton engagement inspire toute la communauté BliGO !'),
      (10, 10000, '🏆 Sommet atteint ! Bravo, tu es officiellement une Légende BliGO. La culture de ta commune te dit un grand MERCI !')
    ) as t(tier, threshold, message)
    where tier > coalesce(v_current_tier, 0) and v_xp >= threshold
    order by tier asc
  loop
    insert into public.notifications (user_id, message) values (p_user_id, r.message);
    update public.profiles set badge_tier = r.tier where id = p_user_id;
  end loop;

  if coalesce(v_plume_xp, 0) >= 150 and not coalesce(v_plume_unlocked, false) then
    insert into public.notifications (user_id, message)
    values (p_user_id, '🌴 Bravo péyi ! Tu as débloqué le badge Plume Locale. Merci de faire rayonner les auteurs et la culture du territoire !');
    update public.profiles set plume_locale_unlocked = true where id = p_user_id;
  end if;

  select count(*) into v_donation_count from public.free_books where donated_by = p_user_id;
  if v_donation_count >= 5 and not coalesce(v_coeur_unlocked, false) then
    insert into public.notifications (user_id, message)
    values (p_user_id, '💛 Un grand Cœur ! Tu as débloqué le badge Cœur Généreux. Grâce à tes dons, tu donnes une seconde vie aux livres !');
    update public.profiles set coeur_genereux_unlocked = true where id = p_user_id;
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

-- 12. Rappels automatiques d'événements (la veille + 2h avant), pour les usagers inscrits.
alter table public.event_rsvps add column if not exists reminded_24h boolean not null default false;
alter table public.event_rsvps add column if not exists reminded_2h boolean not null default false;

create or replace function public.send_event_reminders()
returns void
language plpgsql
security definer
as $$
begin
  insert into public.notifications (user_id, message)
  select er.user_id, 'Rappel : l''événement « ' || e.title || ' » a lieu demain' ||
    (case when e.location is not null then ' à ' || e.location else '' end) || '.'
  from public.event_rsvps er
  join public.events e on e.id = er.event_id
  where er.reminded_24h = false
    and e.event_date > now()
    and e.event_date <= now() + interval '24 hours';

  update public.event_rsvps er
  set reminded_24h = true
  from public.events e
  where er.event_id = e.id
    and er.reminded_24h = false
    and e.event_date > now()
    and e.event_date <= now() + interval '24 hours';

  insert into public.notifications (user_id, message)
  select er.user_id, 'Rappel : l''événement « ' || e.title || ' » commence dans 2h' ||
    (case when e.location is not null then ' à ' || e.location else '' end) || ' !'
  from public.event_rsvps er
  join public.events e on e.id = er.event_id
  where er.reminded_2h = false
    and e.event_date > now()
    and e.event_date <= now() + interval '2 hours';

  update public.event_rsvps er
  set reminded_2h = true
  from public.events e
  where er.event_id = e.id
    and er.reminded_2h = false
    and e.event_date > now()
    and e.event_date <= now() + interval '2 hours';
end;
$$;

select cron.schedule('event-reminders', '*/15 * * * *', $$select public.send_event_reminders();$$);

-- 13. Badge spécial "Cœur Généreux" (5 dons validés au total), pour compléter la grille à 12 badges.
alter table public.profiles add column if not exists coeur_genereux_unlocked boolean not null default false;

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
  v_coeur_unlocked boolean;
  v_donation_count integer;
  r record;
begin
  select loyalty_points, plume_locale_xp, badge_tier, plume_locale_unlocked, coeur_genereux_unlocked
    into v_xp, v_plume_xp, v_current_tier, v_plume_unlocked, v_coeur_unlocked
    from public.profiles where id = p_user_id;

  for r in
    select * from (values
      (1, 30, '📖 Félicitations ! Tu viens de débloquer le badge Premier Chapitre. Ton aventure BliGO commence aujourd''hui !'),
      (2, 100, '🔍 Bravo ! Badge Petit Curieux débloqué. Ta passion pour la lecture commence à porter ses fruits dans le quartier !'),
      (3, 250, '🎯 Bien joué ! Tu as débloqué le badge Dénicheur. Trouver les plus belles pépites de la commune, c''est ta spécialité !'),
      (4, 500, '📚 Super ! Badge Bouquineur débloqué. Déjà 10 livres remis en circulation grâce à toi. Merci pour la communauté !'),
      (5, 1000, '🤝 Impressionnant ! Tu obtiens le badge Passeur de Mots. Ta générosité fait voyager la culture de voisin en voisin !'),
      (6, 2000, '🚀 Quel rythme ! Félicitations, tu as débloqué le badge Dévoreur. Plus rien n''arrête ta soif de lecture !'),
      (7, 3500, '🌟 Chapeau bas ! Le badge Bibliophile est à toi. Un véritable pilier de la lecture partagée au cœur de ta commune !'),
      (8, 5000, '🏰 Incroyable ! Tu décroches le badge Gardien du Savoir. 100 livres partagés, un immense merci pour ce formidable impact local !'),
      (9, 7500, '👑 Légendaire ! Badge Maître des Pages débloqué. Ton engagement inspire toute la communauté BliGO !'),
      (10, 10000, '🏆 Sommet atteint ! Bravo, tu es officiellement une Légende BliGO. La culture de ta commune te dit un grand MERCI !')
    ) as t(tier, threshold, message)
    where tier > coalesce(v_current_tier, 0) and v_xp >= threshold
    order by tier asc
  loop
    insert into public.notifications (user_id, message) values (p_user_id, r.message);
    update public.profiles set badge_tier = r.tier where id = p_user_id;
  end loop;

  if coalesce(v_plume_xp, 0) >= 150 and not coalesce(v_plume_unlocked, false) then
    insert into public.notifications (user_id, message)
    values (p_user_id, '🌴 Bravo péyi ! Tu as débloqué le badge Plume Locale. Merci de faire rayonner les auteurs et la culture du territoire !');
    update public.profiles set plume_locale_unlocked = true where id = p_user_id;
  end if;

  select count(*) into v_donation_count from public.free_books where donated_by = p_user_id;
  if v_donation_count >= 5 and not coalesce(v_coeur_unlocked, false) then
    insert into public.notifications (user_id, message)
    values (p_user_id, '💛 Un grand Cœur ! Tu as débloqué le badge Cœur Généreux. Grâce à tes dons, tu donnes une seconde vie aux livres !');
    update public.profiles set coeur_genereux_unlocked = true where id = p_user_id;
  end if;
end;
$$;

-- 14. "Recevoir une alerte" sur un livre indisponible : réutilise la wishlist.
-- Dès qu'un agent repasse le livre en disponible, les usagers qui l'ont dans
-- leur liste d'envie reçoivent une notification.
create or replace function public.notify_wishlist_on_availability()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.available = true and old.available = false then
    insert into public.notifications (user_id, message)
    select w.user_id, '🔔 Bonne nouvelle ! « ' || new.title || ' » est de nouveau disponible à la médiathèque.'
    from public.wishlist w
    where w.book_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_wishlist_on_availability on public.books;
create trigger trg_notify_wishlist_on_availability
  after update on public.books
  for each row execute procedure public.notify_wishlist_on_availability();

-- 15. Activation explicite des notifications (désactivées par défaut) — condition réelle pour que le trigger d'alerte de disponibilité se déclenche.
alter table public.profiles add column if not exists notifications_enabled boolean not null default false;

create or replace function public.notify_wishlist_on_availability()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.available = true and old.available = false then
    insert into public.notifications (user_id, message)
    select w.user_id, '🔔 Bonne nouvelle ! « ' || new.title || ' » est de nouveau disponible à la médiathèque.'
    from public.wishlist w
    join public.profiles p on p.id = w.user_id
    where w.book_id = new.id and p.notifications_enabled = true;
  end if;
  return new;
end;
$$;

-- 16. Parcours des livres hors condition aligné sur le Click & Collect
-- officiel : statut (en préparation / prêt / récupéré / expiré), délai de 48h
-- avec rappel à 24h, notifications identiques.
create table public.free_book_loans (
  id bigint generated always as identity primary key,
  free_book_id bigint not null references public.free_books(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'preparation' check (status in ('preparation', 'pret', 'recupere', 'expiree')),
  notified_24h boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.free_book_loans enable row level security;

create policy "Un usager voit ses propres emprunts hors condition"
  on public.free_book_loans for select
  using (auth.uid() = user_id);

create policy "Un agent voit tous les emprunts hors condition"
  on public.free_book_loans for select
  using (public.is_agent());

create policy "Un agent met à jour les emprunts hors condition"
  on public.free_book_loans for update
  using (public.is_agent());

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
    insert into public.free_book_loans (free_book_id, user_id, status)
    values (p_book_id, auth.uid(), 'preparation');

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

create or replace function public.notify_on_free_loan_ready()
returns trigger
language plpgsql
security definer
as $$
declare
  v_title text;
begin
  if new.status = 'pret' and old.status is distinct from 'pret' then
    select title into v_title from public.free_books where id = new.free_book_id;
    insert into public.notifications (user_id, message)
    values (new.user_id, 'Votre livre hors condition « ' || coalesce(v_title, '') || ' » est prêt à récupérer à la médiathèque !');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_free_loan_ready on public.free_book_loans;
create trigger trg_notify_on_free_loan_ready
  after update on public.free_book_loans
  for each row execute procedure public.notify_on_free_loan_ready();

create or replace function public.expire_old_free_book_loans()
returns void
language plpgsql
security definer
as $$
declare
  cutoff_48h timestamptz := now() - interval '48 hours';
  cutoff_24h timestamptz := now() - interval '24 hours';
begin
  insert into public.notifications (user_id, message)
  select l.user_id, 'Il vous reste 24h pour récupérer « ' || fb.title || ' » avant qu''il ne soit remis à disposition.'
  from public.free_book_loans l
  join public.free_books fb on fb.id = l.free_book_id
  where l.status in ('preparation', 'pret')
    and l.created_at <= cutoff_24h
    and l.notified_24h = false;

  update public.free_book_loans
  set notified_24h = true
  where status in ('preparation', 'pret') and created_at <= cutoff_24h and notified_24h = false;

  update public.free_books
  set available = true, borrowed_by = null
  where id in (
    select free_book_id from public.free_book_loans
    where status in ('preparation', 'pret') and created_at < cutoff_48h
  );

  update public.free_book_loans
  set status = 'expiree'
  where status in ('preparation', 'pret') and created_at < cutoff_48h;
end;
$$;

select cron.schedule('expire-free-book-loans', '*/15 * * * *', $$select public.expire_old_free_book_loans();$$);

-- 17. Corrige le décompte de retrait (démarre à "prêt", pas à la réservation)
-- + suivi des retours du catalogue officiel (3 semaines + rappel).
alter table public.reservations add column if not exists ready_at timestamptz;
alter table public.reservations add column if not exists return_due_at timestamptz;
alter table public.reservations add column if not exists return_reminded boolean not null default false;
alter table public.reservations add column if not exists reshelved boolean not null default false;

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
    update public.reservations set ready_at = now() where id = new.id;
  end if;

  if new.status = 'recupere' and old.status is distinct from 'recupere' then
    select title into v_title from public.books where id = new.book_id;
    update public.reservations set return_due_at = now() + interval '21 days' where id = new.id;
    insert into public.notifications (user_id, message)
    values (new.user_id, 'Merci ! « ' || coalesce(v_title, '') || ' » est à rapporter à la médiathèque avant le ' || to_char((now() + interval '21 days'), 'DD/MM/YYYY') || '.');
  end if;

  return new;
end;
$$;

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
  where r.status = 'pret'
    and r.ready_at <= cutoff_24h
    and r.notified_24h = false;

  update public.reservations
  set notified_24h = true
  where status = 'pret' and ready_at <= cutoff_24h and notified_24h = false;

  update public.books
  set available = true
  where id in (
    select book_id from public.reservations
    where status = 'pret' and ready_at < cutoff_48h
  );

  update public.reservations
  set status = 'expiree'
  where status = 'pret' and ready_at < cutoff_48h;
end;
$$;

create or replace function public.remind_upcoming_returns()
returns void
language plpgsql
security definer
as $$
begin
  insert into public.notifications (user_id, message)
  select r.user_id, 'Pense à rapporter « ' || b.title || ' » à la médiathèque avant le ' || to_char(r.return_due_at, 'DD/MM/YYYY') || '.'
  from public.reservations r
  join public.books b on b.id = r.book_id
  where r.status = 'recupere'
    and r.return_reminded = false
    and r.return_due_at is not null
    and r.return_due_at <= now() + interval '3 days';

  update public.reservations
  set return_reminded = true
  where status = 'recupere' and return_reminded = false and return_due_at is not null and return_due_at <= now() + interval '3 days';
end;
$$;

select cron.schedule('remind-upcoming-returns', '0 9 * * *', $$select public.remind_upcoming_returns();$$);

-- Un avis ne peut être laissé que sur un livre réellement emprunté et rendu
-- (visible dans l'historique), jamais depuis le catalogue avant même de
-- l'avoir lu. Le catalogue n'affiche que les avis déjà existants.
drop policy if exists "Un usager dépose son propre avis" on public.book_reviews;
create policy "Un usager dépose un avis uniquement sur un livre emprunté et rendu"
  on public.book_reviews for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.reservations r
      where r.user_id = auth.uid()
        and r.book_id = book_reviews.book_id
        and r.status = 'recupere'
        and r.return_due_at is not null
        and r.return_due_at <= now()
    )
  );

drop policy if exists "Un usager modifie son propre avis" on public.book_reviews;
create policy "Un usager modifie un avis uniquement sur un livre emprunté et rendu"
  on public.book_reviews for update
  using (
    auth.uid() = user_id
    and exists (
      select 1 from public.reservations r
      where r.user_id = auth.uid()
        and r.book_id = book_reviews.book_id
        and r.status = 'recupere'
        and r.return_due_at is not null
        and r.return_due_at <= now()
    )
  );

-- Notification une fois le livre rendu (délai de 3 semaines écoulé), pour
-- inviter l'usager à le noter dans son historique de réservations.
alter table public.reservations add column if not exists review_reminded boolean not null default false;

create or replace function public.remind_to_review_returned_books()
returns void
language plpgsql
security definer
as $$
begin
  insert into public.notifications (user_id, message)
  select r.user_id, 'Alors, qu''as-tu pensé de « ' || b.title || ' » ? Donne ton avis dans ton historique de réservations !'
  from public.reservations r
  join public.books b on b.id = r.book_id
  where r.status = 'recupere'
    and r.review_reminded = false
    and r.return_due_at is not null
    and r.return_due_at <= now();

  update public.reservations
  set review_reminded = true
  where status = 'recupere' and review_reminded = false and return_due_at is not null and return_due_at <= now();
end;
$$;

select cron.schedule('remind-to-review-returned-books', '0 10 * * *', $$select public.remind_to_review_returned_books();$$);

-- Même correction pour les livres hors condition.
alter table public.free_book_loans add column if not exists ready_at timestamptz;

create or replace function public.notify_on_free_loan_ready()
returns trigger
language plpgsql
security definer
as $$
declare
  v_title text;
begin
  if new.status = 'pret' and old.status is distinct from 'pret' then
    select title into v_title from public.free_books where id = new.free_book_id;
    insert into public.notifications (user_id, message)
    values (new.user_id, 'Votre livre hors condition « ' || coalesce(v_title, '') || ' » est prêt à récupérer à la médiathèque !');
    update public.free_book_loans set ready_at = now() where id = new.id;
  end if;
  return new;
end;
$$;

create or replace function public.expire_old_free_book_loans()
returns void
language plpgsql
security definer
as $$
declare
  cutoff_48h timestamptz := now() - interval '48 hours';
  cutoff_24h timestamptz := now() - interval '24 hours';
begin
  insert into public.notifications (user_id, message)
  select l.user_id, 'Il vous reste 24h pour récupérer « ' || fb.title || ' » avant qu''il ne soit remis à disposition.'
  from public.free_book_loans l
  join public.free_books fb on fb.id = l.free_book_id
  where l.status = 'pret'
    and l.ready_at <= cutoff_24h
    and l.notified_24h = false;

  update public.free_book_loans
  set notified_24h = true
  where status = 'pret' and ready_at <= cutoff_24h and notified_24h = false;

  update public.free_books
  set available = true, borrowed_by = null
  where id in (
    select free_book_id from public.free_book_loans
    where status = 'pret' and ready_at < cutoff_48h
  );

  update public.free_book_loans
  set status = 'expiree'
  where status = 'pret' and ready_at < cutoff_48h;
end;
$$;

-- 18. Limite le nombre de livres en cours par usager : 3 maximum hors
-- jeunesse, + 3 maximum en catégorie Jeunesse. Le catalogue officiel et les
-- livres hors condition ont chacun leur propre quota, indépendant l'un de
-- l'autre.
create or replace function public.enforce_reservation_limits()
returns trigger
language plpgsql
security definer
as $$
declare
  v_category text;
  v_is_jeunesse boolean;
  v_active_count integer;
  v_duplicate_count integer;
begin
  if tg_table_name = 'reservations' then
    -- Empêche de réserver un livre déjà en cours (réservé ou emprunté et pas
    -- encore rendu) une deuxième fois.
    select count(*) into v_duplicate_count
    from public.reservations r
    where r.user_id = new.user_id
      and r.book_id = new.book_id
      and (
        r.status in ('preparation', 'pret')
        or (r.status = 'recupere' and r.return_due_at is not null and r.return_due_at > now())
      );

    if v_duplicate_count > 0 then
      raise exception 'Tu as déjà ce livre en cours (réservé ou emprunté) — impossible de le réserver une deuxième fois avant de l''avoir rendu.';
    end if;

    select category into v_category from public.books where id = new.book_id;
    select count(*) into v_active_count
    from public.reservations r
    join public.books b on b.id = r.book_id
    where r.user_id = new.user_id
      and (
        r.status in ('preparation', 'pret')
        or (r.status = 'recupere' and r.return_due_at is not null and r.return_due_at > now())
      )
      and coalesce(b.category = 'Jeunesse', false) = coalesce(v_category = 'Jeunesse', false);
  else
    select category into v_category from public.free_books where id = new.free_book_id;
    select count(*) into v_active_count
    from public.free_book_loans l
    join public.free_books fb on fb.id = l.free_book_id
    where l.user_id = new.user_id and l.status in ('preparation', 'pret')
      and coalesce(fb.category = 'Jeunesse', false) = coalesce(v_category = 'Jeunesse', false);
  end if;

  v_is_jeunesse := (v_category = 'Jeunesse');

  if v_active_count >= 3 then
    if v_is_jeunesse then
      raise exception 'Limite atteinte : 3 livres jeunesse maximum en cours à la fois.';
    elsif tg_table_name = 'reservations' then
      raise exception 'Limite atteinte : 3 livres maximum en cours à la fois (hors jeunesse). Rapportez-en un pour en réserver un nouveau, ou prenez un livre hors condition avec « Prendre ce livre ».';
    else
      raise exception 'Limite atteinte : 3 livres hors condition maximum en cours à la fois (hors jeunesse). Rapportez-en un pour en prendre un nouveau.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_reservation_limits on public.reservations;
create trigger trg_enforce_reservation_limits
  before insert on public.reservations
  for each row execute procedure public.enforce_reservation_limits();

drop trigger if exists trg_enforce_free_loan_limits on public.free_book_loans;
create trigger trg_enforce_free_loan_limits
  before insert on public.free_book_loans
  for each row execute procedure public.enforce_reservation_limits();
