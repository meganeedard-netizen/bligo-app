-- BliGO — schéma de base de données (Médiathèque de Val-Fleuri, commune pilote)
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

-- 1. Profils usagers (complète auth.users géré par Supabase Auth)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  subscriber_number text unique not null,
  account_type text not null default 'flash' check (account_type in ('officiel', 'flash')),
  loyalty_points integer not null default 0,
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
      'Roman', 'Thriller', 'Science-fiction', 'Littérature antillaise', 'BD', 'Mangas',
      'Jeunesse', 'Développement personnel', 'Autobiographie', 'Santé', 'Histoire', 'Sport', 'Magazine', 'Autre'
    )
  ),
  summary text,
  cover_url text,
  is_featured boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.books enable row level security;

create policy "Le catalogue est public en lecture"
  on public.books for select
  using (true);

insert into public.books (title, author, cover_initial, available, category, summary, cover_url) values
  ('Texaco', 'Patrick Chamoiseau', 'T', true, 'Littérature antillaise', 'Fresque d''un quartier populaire de Martinique à travers plusieurs générations d''une famille créole, de la période coloniale à l''urbanisation moderne. Prix Goncourt 1992.', null),
  ('Pluie et vent sur Télumée Miracle', 'Simone Schwarz-Bart', 'P', false, 'Littérature antillaise', 'La vie de Télumée, une femme guadeloupéenne confrontée à l''amour, aux épreuves et à la résilience à travers les générations. Un texte fondateur de la littérature caribéenne.', null),
  ('Une si longue lettre', 'Mariama Bâ', 'U', true, 'Roman', 'Une veuve sénégalaise écrit une longue lettre à sa meilleure amie, méditant sur le mariage, la polygamie et la condition des femmes dans l''Afrique post-coloniale.', null),
  ('Cahier d''un retour au pays natal', 'Aimé Césaire', 'C', false, 'Littérature antillaise', 'Long poème fondateur du mouvement de la Négritude, méditation lyrique sur l''identité, la colonisation et l''héritage martiniquais et africain.', null),
  ('Ti Jean L''horizon', 'Simone Schwarz-Bart', 'T', true, 'Littérature antillaise', 'Un conte initiatique et fantastique suivant Ti Jean dans une quête mêlant folklore caribéen, magie et recherche d''identité.', null),
  ('Les Soleils des indépendances', 'Ahmadou Kourouma', 'S', true, 'Roman', 'Portrait satirique d''un prince africain déchu, confronté aux désillusions des jeunes nations africaines nouvellement indépendantes.', null),
  ('L''Étranger', 'Albert Camus', 'É', true, 'Roman', 'Meursault, employé indifférent à Alger, commet un acte de violence absurde et affronte l''exigence de sens de la société. Un classique de la littérature existentialiste.', null),
  ('La Saison de l''ombre', 'Léonora Miano', 'L', false, 'Roman', 'Un village africain confronté à la disparition de ses jeunes hommes à l''aube de la traite négrière transatlantique. Prix Goncourt des lycéens 2013.', null),
  ('Le dîner. Une aventure dont vous êtes le héros', 'Freida McFadden', 'D', true, 'Thriller', 'Un dîner qui tourne au cauchemar : secrets, manipulation et tension psychologique dans ce thriller à l''intrigue redoutable.', 'img/covers/le-diner.jpg'),
  ('La prof', 'Freida McFadden', 'P', false, 'Thriller', 'Un thriller psychologique haletant autour d''une professeure dont le passé cache de sombres secrets, jusqu''au twist final.', 'img/covers/la-prof.jpg'),
  ('Les heures fragiles', 'Virginie Grimaldi', 'H', true, 'Roman', 'Un roman chaleureux et plein de vie sur des destins ordinaires qui se croisent à des moments fragiles, entre résilience et lien humain.', 'img/covers/les-heures-fragiles.jpg'),
  ('Tata', 'Valérie Perrin', 'T', true, 'Roman', 'Une saga familiale tendre et bouleversante explorant les secrets et les liens entre plusieurs générations de femmes.', 'img/covers/tata.jpg'),
  ('La psy', 'Freida McFadden', 'P', false, 'Thriller', 'Les séances d''une psychothérapeute basculent dans une toile de manipulation et de danger, dans ce thriller psychologique addictif.', 'img/covers/la-psy.jpg'),
  ('Quelqu''un d''autre', 'Guillaume Musso', 'Q', true, 'Thriller', 'Un thriller sur l''identité et les vies qu''on aurait pu vivre, avec les retournements de situation caractéristiques de Guillaume Musso.', 'img/covers/quelquun-dautre.jpg'),
  ('La femme de ménage', 'Freida McFadden', 'F', false, 'Thriller', 'Une femme sans domicile devient gouvernante dans une famille aisée, et se retrouve prise dans un engrenage de mensonges et de danger.', 'img/covers/femme-de-menage.jpg'),
  ('Celle qui sait', 'Riley Sager', 'C', true, 'Thriller', 'Un thriller à suspense où le passé trouble d''une femme refait surface, l''obligeant à affronter des secrets qu''elle croyait enterrés.', 'img/covers/celle-qui-sait.jpg'),
  ('La femme de ménage voit tout', 'Freida McFadden', 'F', true, 'Thriller', 'La suite de « La femme de ménage » : la nouvelle vie de Millie se fissure quand d''anciens secrets et de nouvelles menaces se percutent.', 'img/covers/femme-de-menage-voit-tout.jpg'),
  ('Les secrets de la femme de ménage', 'Freida McFadden', 'S', false, 'Thriller', 'La saga continue : Millie affronte un nouveau danger tandis que des vérités enfouies menacent la paix fragile qu''elle a construite.', null),
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
  ('Résister', 'Salomé Saqué', 'R', true, 'Autre', 'Un essai engagé sur les mobilisations citoyennes et politiques contemporaines, par la journaliste Salomé Saqué.', 'img/covers/resister.jpg'),
  ('Tout le monde aime Clara', 'David Foenkinos', 'T', false, 'Roman', 'Foenkinos signe un roman choral plein de finesse autour du destin de Clara, entre légèreté et profondeur.', 'img/covers/tout-le-monde-aime-clara.jpg'),
  ('Un avenir radieux', 'Pierre Lemaitre', 'U', true, 'Roman', 'Pierre Lemaitre déploie une fresque romanesque ambitieuse, entre satire sociale et sens du récit.', 'img/covers/un-avenir-radieux.jpg'),
  ('Un jour sans femme', 'Laetitia Colombani', 'U', true, 'Roman', 'Laetitia Colombani interroge la condition féminine à travers un récit poignant et engagé.', 'img/covers/un-jour-sans-femme.jpg'),
  ('Une unique lueur', 'Fred Vargas', 'U', false, 'Thriller', 'Une nouvelle enquête du commissaire Adamsberg, portée par l''univers singulier et atmosphérique de Fred Vargas.', 'img/covers/une-unique-lueur.jpg');

update public.books set is_featured = true where title = 'Texaco';

-- 3. Réservations Click & Collect
create table public.reservations (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id bigint not null references public.books(id) on delete cascade,
  status text not null default 'preparation' check (status in ('preparation', 'pret', 'recupere', 'expiree')),
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

-- Expiration automatique des réservations non récupérées sous 48h :
-- remet le livre en rayon et marque la réservation comme expirée.
create or replace function public.expire_old_reservations()
returns void
language plpgsql
security definer
as $$
declare
  cutoff timestamptz := now() - interval '48 hours';
begin
  update public.books
  set available = true
  where id in (
    select book_id from public.reservations
    where status in ('preparation', 'pret') and created_at < cutoff
  );

  update public.reservations
  set status = 'expiree'
  where status in ('preparation', 'pret') and created_at < cutoff;
end;
$$;

create extension if not exists pg_cron with schema extensions;

select cron.schedule('expire-reservations', '*/15 * * * *', $$select public.expire_old_reservations();$$);
