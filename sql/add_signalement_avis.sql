-- Signalement et modération des avis (23/10/2026)
-- Exigence Apple (règle 1.2, contenu créé par les utilisateurs) :
--   1. un usager peut signaler un avis ;
--   2. un usager peut ne plus voir les avis d'un auteur ;
--   3. la médiathèque peut supprimer un avis et bloquer un auteur ;
--   4. un filtre refuse les avis contenant des mots injurieux.
-- À lancer une seule fois dans le SQL Editor de Supabase (relançable sans risque).

-- ============================================================
-- 1. Signalements
-- ============================================================
create table if not exists public.review_reports (
  id bigint generated always as identity primary key,
  review_id bigint not null references public.book_reviews(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (reason in ('injurieux', 'hors_sujet', 'divulgacheur', 'autre')),
  status text not null default 'nouveau' check (status in ('nouveau', 'traite')),
  created_at timestamptz not null default now(),
  unique (review_id, reporter_id)
);

alter table public.review_reports enable row level security;

drop policy if exists "Un usager signale un avis" on public.review_reports;
create policy "Un usager signale un avis"
  on public.review_reports for insert
  with check (auth.uid() = reporter_id);

drop policy if exists "Un usager voit ses signalements" on public.review_reports;
create policy "Un usager voit ses signalements"
  on public.review_reports for select
  using (auth.uid() = reporter_id);

-- ============================================================
-- 2. Auteurs masqués par un usager (« Ne plus voir ses avis »)
-- ============================================================
create table if not exists public.review_author_mutes (
  user_id uuid not null references auth.users(id) on delete cascade,
  muted_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, muted_user_id)
);

alter table public.review_author_mutes enable row level security;

drop policy if exists "Un usager gère ses auteurs masqués" on public.review_author_mutes;
create policy "Un usager gère ses auteurs masqués"
  on public.review_author_mutes for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================================
-- 3. Blocage d'un auteur par la médiathèque
-- ============================================================
alter table public.profiles add column if not exists reviews_blocked boolean not null default false;

drop policy if exists "Un usager dépose un avis uniquement sur un livre emprunté et rendu" on public.book_reviews;
create policy "Un usager dépose un avis uniquement sur un livre emprunté et rendu"
  on public.book_reviews for insert
  with check (
    auth.uid() = user_id
    and not exists (select 1 from public.profiles p where p.id = auth.uid() and p.reviews_blocked)
    and exists (
      select 1 from public.reservations r
      where r.user_id = auth.uid()
        and r.book_id = book_reviews.book_id
        and r.status = 'recupere'
        and r.return_due_at is not null
        and r.return_due_at <= now()
    )
  );

drop policy if exists "Un usager modifie un avis uniquement sur un livre emprunté et rendu" on public.book_reviews;
create policy "Un usager modifie un avis uniquement sur un livre emprunté et rendu"
  on public.book_reviews for update
  using (
    auth.uid() = user_id
    and not exists (select 1 from public.profiles p where p.id = auth.uid() and p.reviews_blocked)
    and exists (
      select 1 from public.reservations r
      where r.user_id = auth.uid()
        and r.book_id = book_reviews.book_id
        and r.status = 'recupere'
        and r.return_due_at is not null
        and r.return_due_at <= now()
    )
  );

-- ============================================================
-- 4. Filtre de mots injurieux
-- ============================================================
-- Liste volontairement courte (insultes courantes) : le signalement et la
-- modération par la médiathèque restent le vrai garde-fou.
create or replace function public.check_review_comment()
returns trigger
language plpgsql
as $$
declare
  v_text text;
begin
  if new.comment is null then return new; end if;
  v_text := lower(translate(new.comment, 'àâäéèêëîïôöùûüç', 'aaaeeeeiioouuuc'));
  if v_text ~ '\m(con|conne|connard|connasse|salope|salaud|pute|putain|encule|enculee|batard|batarde|pd|tapette|negro|bougnoule|youpin|bite|couille|couilles|nique|niquer|ntm|fdp|merde|abruti|abrutie|debile|gogol)\M' then
    raise exception 'Ton avis contient des mots qui ne sont pas autorisés. Reformule-le et réessaie.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_check_review_comment on public.book_reviews;
create trigger trg_check_review_comment
  before insert or update of comment on public.book_reviews
  for each row execute procedure public.check_review_comment();

-- ============================================================
-- 5. Outils de modération pour les agents
-- ============================================================
-- Avis signalés (non traités) des livres de la médiathèque de l'agent ;
-- toutes les médiathèques pour un super admin.
create or replace function public.reported_reviews()
returns table (
  review_id bigint,
  book_id bigint,
  book_title text,
  rating integer,
  comment text,
  review_created_at timestamptz,
  author_id uuid,
  author_name text,
  author_blocked boolean,
  report_count bigint,
  reasons text[],
  last_report_at timestamptz
)
language plpgsql
security definer
set search_path = public
stable
as $$
#variable_conflict use_column
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Réservé aux agents';
  end if;
  return query
  select rv.id, b.id, b.title, rv.rating, rv.comment, rv.created_at,
         rv.user_id, p.full_name, coalesce(p.reviews_blocked, false),
         count(rr.id), array_agg(distinct rr.reason), max(rr.created_at)
  from public.review_reports rr
  join public.book_reviews rv on rv.id = rr.review_id
  join public.books b on b.id = rv.book_id
  left join public.profiles p on p.id = rv.user_id
  where rr.status = 'nouveau'
    and (public.is_super_admin() or public.agent_commune_id() is null or b.commune_id = public.agent_commune_id())
  group by rv.id, b.id, b.title, rv.rating, rv.comment, rv.created_at, rv.user_id, p.full_name, p.reviews_blocked
  order by max(rr.created_at) desc;
end;
$$;

-- p_action : 'supprimer' (efface l'avis) ou 'garder' (classe les signalements).
create or replace function public.moderate_review(p_review_id bigint, p_action text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commune bigint;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Réservé aux agents';
  end if;
  select b.commune_id into v_commune
  from public.book_reviews rv join public.books b on b.id = rv.book_id
  where rv.id = p_review_id;
  if not found then return; end if;
  if not (public.is_super_admin() or public.agent_commune_id() is null or v_commune = public.agent_commune_id()) then
    raise exception 'Cet avis concerne une autre médiathèque';
  end if;

  if p_action = 'supprimer' then
    delete from public.book_reviews where id = p_review_id;
  elsif p_action = 'garder' then
    update public.review_reports set status = 'traite' where review_id = p_review_id;
  else
    raise exception 'Action inconnue : %', p_action;
  end if;
end;
$$;

-- Bloque (ou débloque) un auteur : il ne peut plus publier ni modifier d'avis.
-- Au blocage, ses avis existants sont supprimés.
create or replace function public.set_review_author_blocked(p_user_id uuid, p_blocked boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Réservé aux agents';
  end if;
  update public.profiles set reviews_blocked = p_blocked where id = p_user_id;
  if p_blocked then
    delete from public.book_reviews where user_id = p_user_id;
  end if;
end;
$$;

grant execute on function public.reported_reviews() to authenticated;
grant execute on function public.moderate_review(bigint, text) to authenticated;
grant execute on function public.set_review_author_blocked(uuid, boolean) to authenticated;
