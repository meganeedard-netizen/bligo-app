-- BliGO — Tendances d'emprunt et Sélection du mois (14/09/2026)
-- Aide les agents à choisir quoi racheter : livres/auteurs les plus empruntés,
-- et un top 20 mensuel saisi à la main par l'administratrice BliGO en s'appuyant
-- sur un vrai classement des ventes en librairie (Livres Hebdo, Edistat...).
--
-- Prérequis : add_copies_communities_loans.sql (agent_commune_id, communities)
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run


-- ============================================================
-- 1. Sélection du mois (saisie manuelle par l'administratrice BliGO)
-- ============================================================
-- Réservé aux agents en lecture : ce n'est pas montré dans l'appli usager
-- (décision du 14/09/2026), c'est un outil d'aide à l'achat.

create table if not exists public.monthly_top_books (
  id bigint generated always as identity primary key,

  -- Premier jour du mois concerné, ex. 2026-09-01
  month date not null,
  rank integer not null check (rank between 1 and 20),

  title text not null,
  author text not null,
  isbn text,
  cover_url text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (month, rank)
);

create index if not exists monthly_top_books_month_idx on public.monthly_top_books (month);

alter table public.monthly_top_books enable row level security;

create policy "Les agents lisent la sélection du mois"
  on public.monthly_top_books for select
  using (public.is_agent() or public.is_super_admin());

create policy "Seule l'administratrice BliGO gère la sélection du mois"
  on public.monthly_top_books for all
  using (public.is_super_admin())
  with check (public.is_super_admin());

create or replace function public.touch_monthly_top_books()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists touch_monthly_top_books_trigger on public.monthly_top_books;

create trigger touch_monthly_top_books_trigger
  before update on public.monthly_top_books
  for each row execute function public.touch_monthly_top_books();


-- ============================================================
-- 2. Tendances d'emprunt (livres et auteurs les plus lus)
-- ============================================================
-- Signal compté depuis deux sources :
--   - la table `loans`, précise, alimentée par les scans depuis le 13/09/2026
--   - les réservations déjà marquées 'recupere' avant cette date, comptées comme
--     emprunt pour la statistique. On ne leur invente pas de date de retour :
--     `loans` reste la seule source fiable pour le suivi physique d'un exemplaire,
--     ce UNION ne sert qu'au comptage.
-- Sans ce repêchage, les tendances repartiraient de zéro alors que l'historique
-- d'emprunt existe déjà.

create or replace function public.stats_top_books(
  p_scope text default 'commune',   -- 'commune' | 'community'
  p_since timestamptz default null, -- null = depuis toujours
  p_limit integer default 20
)
returns table (
  book_id bigint,
  title text,
  author text,
  cover_url text,
  category text,
  loan_count bigint
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_commune bigint := public.agent_commune_id();
  v_community bigint;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  if p_scope not in ('commune', 'community') then
    raise exception 'Périmètre invalide : % (attendu commune ou community)', p_scope;
  end if;

  select community_id into v_community from public.communes where id = v_commune;

  return query
  with events as (
    select bc.book_id as book_id, l.borrowed_at_commune_id as commune_id, l.borrowed_at as event_at
    from public.loans l
    join public.book_copies bc on bc.id = l.copy_id
    union all
    select r.book_id, b.commune_id, r.created_at
    from public.reservations r
    join public.books b on b.id = r.book_id
    where r.status = 'recupere'
      and not exists (select 1 from public.loans l2 where l2.reservation_id = r.id)
  )
  select b.id, b.title, b.author, b.cover_url, b.category, count(*)::bigint as loan_count
  from events e
  join public.books b on b.id = e.book_id
  where (p_since is null or e.event_at >= p_since)
    and (
      (p_scope = 'commune' and v_commune is not null and e.commune_id = v_commune)
      or (p_scope = 'community' and v_community is not null and e.commune_id in (
            select id from public.communes where community_id = v_community
          ))
    )
  group by b.id, b.title, b.author, b.cover_url, b.category
  order by loan_count desc, b.title
  limit p_limit;
end;
$$;

create or replace function public.stats_top_authors(
  p_scope text default 'commune',
  p_since timestamptz default null,
  p_limit integer default 20
)
returns table (
  author text,
  loan_count bigint,
  distinct_titles bigint
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_commune bigint := public.agent_commune_id();
  v_community bigint;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  if p_scope not in ('commune', 'community') then
    raise exception 'Périmètre invalide : % (attendu commune ou community)', p_scope;
  end if;

  select community_id into v_community from public.communes where id = v_commune;

  return query
  with events as (
    select bc.book_id as book_id, l.borrowed_at_commune_id as commune_id, l.borrowed_at as event_at
    from public.loans l
    join public.book_copies bc on bc.id = l.copy_id
    union all
    select r.book_id, b.commune_id, r.created_at
    from public.reservations r
    join public.books b on b.id = r.book_id
    where r.status = 'recupere'
      and not exists (select 1 from public.loans l2 where l2.reservation_id = r.id)
  )
  select b.author, count(*)::bigint as loan_count, count(distinct b.id)::bigint as distinct_titles
  from events e
  join public.books b on b.id = e.book_id
  where (p_since is null or e.event_at >= p_since)
    and (
      (p_scope = 'commune' and v_commune is not null and e.commune_id = v_commune)
      or (p_scope = 'community' and v_community is not null and e.commune_id in (
            select id from public.communes where community_id = v_community
          ))
    )
  group by b.author
  order by loan_count desc, b.author
  limit p_limit;
end;
$$;
