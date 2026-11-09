-- Modération des avis par l'IA + modération réservée au super admin (09/11/2026)
-- Demande de Mégane : les agents ne voient plus et ne suppriment plus les avis ;
-- seule Mégane (super admin) gère les signalements ; tout avis injurieux,
-- haineux, prosélyte (religion, secte), harcelant, etc. est bloqué
-- automatiquement avant publication.
--
-- Fonctionnement :
--   1. le filtre de mots (trg_check_review_comment) refuse tout de suite les
--      insultes les plus évidentes ;
--   2. tout nouveau commentaire (ou commentaire modifié) n'est PAS publié :
--      il part dans book_review_pending, et la note seule reste visible ;
--   3. l'Edge Function moderer-avis le fait lire par l'IA : acceptable, il est
--      publié ; sinon il est jeté et noté dans review_moderation_log (visible
--      par le super admin) ;
--   4. si l'IA ne répond pas, un cron relance toutes les 5 minutes.
-- Relançable sans risque.

-- Appels HTTP depuis la base (vers l'Edge Function moderer-avis).
create extension if not exists pg_net;

-- ============================================================
-- 1. Commentaires en attente de vérification (jamais publics)
-- ============================================================
create table if not exists public.book_review_pending (
  review_id bigint primary key references public.book_reviews(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  comment text not null,
  created_at timestamptz not null default now(),
  tentatives integer not null default 0
);

alter table public.book_review_pending enable row level security;

drop policy if exists "Un usager voit son commentaire en attente" on public.book_review_pending;
create policy "Un usager voit son commentaire en attente"
  on public.book_review_pending for select
  using (auth.uid() = user_id);

-- ============================================================
-- 2. Journal des avis refusés (super admin seulement)
-- ============================================================
create table if not exists public.review_moderation_log (
  id bigint generated always as identity primary key,
  review_id bigint,
  book_id bigint,
  user_id uuid references auth.users(id) on delete set null,
  comment text not null,
  categorie text not null,
  raison text,
  source text not null default 'ia' check (source in ('ia', 'mots', 'nettoyage')),
  created_at timestamptz not null default now()
);

alter table public.review_moderation_log enable row level security;

drop policy if exists "Le super admin lit le journal de modération" on public.review_moderation_log;
create policy "Le super admin lit le journal de modération"
  on public.review_moderation_log for select
  using (public.is_super_admin());

-- ============================================================
-- 3. Filtre de mots élargi (refus immédiat, message à l'usager)
-- ============================================================
-- Normalisation : accents retirés, chiffres façon « leet » (3→e, 0→o…),
-- lettres répétées réduites (« connnnard » → « connard »).
create or replace function public.check_review_comment()
returns trigger
language plpgsql
as $$
declare
  v_text text;
begin
  if new.comment is null then return new; end if;
  if tg_op = 'UPDATE' and new.comment is not distinct from old.comment then return new; end if;
  v_text := lower(translate(new.comment, 'àâäáãéèêëíîïóôöõùûüúçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucaaaeeeeiioouuuc'));
  v_text := translate(v_text, '013457@$', 'oieastas');
  v_text := regexp_replace(v_text, '(.)\1{2,}', '\1', 'g');
  if v_text ~ ('\m(con|conne|connard|connards|connasse|salope|salopes|salaud|salauds|pute|putes|putain|enculer|encule|enculee|encules|batard|batarde|batards|pd|pede|pedes|tapette|tarlouze|gouine|negro|negre|negresse|bougnoule|bougnoul|youpin|youpine|feuj|bicot|raton|chinetoque|bamboula|macaque|bite|couille|couilles|nique|niquer|niquez|ntm|fdp|tg|ta gueule|ferme ta gueule|merde|abruti|abrutie|debile|gogol|mongol|attarde|attardee|trisomique|clochard|pouffiasse|grognasse|chienne|catin|traine|trainee|kouni|koukoun|makoume|makome|bouzin|bouzen|manman w|creve|crevez)\M')
     or v_text ~ '(sale (noir|noire|arabe|juif|juive|blanc|blanche|chinois|chinoise|musulman|musulmane|immigre|immigree|pede|gouine|race)|nique (ta|sa|vos|leur) |va te pendre|suicide[ -]toi|tue[ -]toi|je vais te tuer|on va te tuer|mort aux )' then
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
-- 4. Tout commentaire passe par la vérification IA
-- ============================================================
-- Le déclencheur s'exécute après trg_check_review_comment (ordre alphabétique).
-- Seule l'Edge Function (rôle service_role) peut publier un commentaire.
create or replace function public.hold_review_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Publication par l'Edge Function (service_role) ou depuis le SQL Editor.
  if coalesce(auth.role(), '') = 'service_role' or auth.uid() is null then
    return new;
  end if;
  if new.comment is null or btrim(new.comment) = '' then
    new.comment := null;
    return new;
  end if;
  if tg_op = 'UPDATE' and new.comment is not distinct from old.comment then
    return new;
  end if;
  -- Le texte attend dans book_review_pending (rempli après l'écriture, voir
  -- queue_review_comment) ; l'avis garde son ancien commentaire publié.
  perform set_config('bligo.commentaire_en_attente', new.comment, true);
  new.comment := case when tg_op = 'UPDATE' then old.comment else null end;
  return new;
end;
$$;

drop trigger if exists trg_moderation_avis on public.book_reviews;
create trigger trg_moderation_avis
  before insert or update of comment on public.book_reviews
  for each row execute procedure public.hold_review_comment();

create or replace function public.queue_review_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_comment text := nullif(current_setting('bligo.commentaire_en_attente', true), '');
begin
  if v_comment is null then return null; end if;
  perform set_config('bligo.commentaire_en_attente', '', true);
  insert into public.book_review_pending (review_id, user_id, comment)
  values (new.id, new.user_id, v_comment)
  on conflict (review_id) do update set comment = excluded.comment, created_at = now(), tentatives = 0;
  -- Vérification tout de suite (appel asynchrone, après validation de l'écriture).
  perform net.http_post(
    url := 'https://knlymrujmiapzieavzoe.supabase.co/functions/v1/moderer-avis',
    body := jsonb_build_object('review_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json')
  );
  return null;
end;
$$;

drop trigger if exists trg_moderation_avis_file on public.book_reviews;
create trigger trg_moderation_avis_file
  after insert or update on public.book_reviews
  for each row execute procedure public.queue_review_comment();

-- Relance des commentaires restés en attente (IA indisponible…).
do $$
begin
  perform cron.unschedule('moderation-avis-relance');
exception when others then null;
end $$;

select cron.schedule('moderation-avis-relance', '*/5 * * * *', $cron$
  select net.http_post(
    url := 'https://knlymrujmiapzieavzoe.supabase.co/functions/v1/moderer-avis',
    body := jsonb_build_object('review_id', p.review_id),
    headers := jsonb_build_object('Content-Type', 'application/json')
  )
  from public.book_review_pending p
  where p.created_at < now() - interval '2 minutes' and p.tentatives < 20;
$cron$);

-- ============================================================
-- 5. Signalements : réservés au super admin (plus aux agents)
-- ============================================================
drop function if exists public.reported_reviews();
create or replace function public.reported_reviews()
returns table (
  review_id bigint,
  book_id bigint,
  book_title text,
  commune_name text,
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
  if not public.is_super_admin() then
    raise exception 'Réservé à l''administratrice de BliGO';
  end if;
  return query
  select rv.id, b.id, b.title, c.name, rv.rating, rv.comment, rv.created_at,
         rv.user_id, p.full_name, coalesce(p.reviews_blocked, false),
         count(rr.id), array_agg(distinct rr.reason), max(rr.created_at)
  from public.review_reports rr
  join public.book_reviews rv on rv.id = rr.review_id
  join public.books b on b.id = rv.book_id
  left join public.communes c on c.id = b.commune_id
  left join public.profiles p on p.id = rv.user_id
  where rr.status = 'nouveau'
  group by rv.id, b.id, b.title, c.name, rv.rating, rv.comment, rv.created_at, rv.user_id, p.full_name, p.reviews_blocked
  order by max(rr.created_at) desc;
end;
$$;

create or replace function public.moderate_review(p_review_id bigint, p_action text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Réservé à l''administratrice de BliGO';
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

create or replace function public.set_review_author_blocked(p_user_id uuid, p_blocked boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Réservé à l''administratrice de BliGO';
  end if;
  update public.profiles set reviews_blocked = p_blocked where id = p_user_id;
  if p_blocked then
    delete from public.book_reviews where user_id = p_user_id;
  end if;
end;
$$;

-- Avis refusés automatiquement (30 derniers jours), avec l'auteur.
create or replace function public.refused_reviews()
returns table (
  id bigint,
  book_title text,
  comment text,
  categorie text,
  raison text,
  source text,
  created_at timestamptz,
  author_id uuid,
  author_name text,
  author_blocked boolean,
  refus_auteur bigint
)
language plpgsql
security definer
set search_path = public
stable
as $$
#variable_conflict use_column
begin
  if not public.is_super_admin() then
    raise exception 'Réservé à l''administratrice de BliGO';
  end if;
  return query
  select l.id, b.title, l.comment, l.categorie, l.raison, l.source, l.created_at,
         l.user_id, p.full_name, coalesce(p.reviews_blocked, false),
         (select count(*) from public.review_moderation_log l2 where l2.user_id = l.user_id)
  from public.review_moderation_log l
  left join public.books b on b.id = l.book_id
  left join public.profiles p on p.id = l.user_id
  where l.created_at > now() - interval '30 days'
  order by l.created_at desc;
end;
$$;

grant execute on function public.reported_reviews() to authenticated;
grant execute on function public.moderate_review(bigint, text) to authenticated;
grant execute on function public.set_review_author_blocked(uuid, boolean) to authenticated;
grant execute on function public.refused_reviews() to authenticated;
