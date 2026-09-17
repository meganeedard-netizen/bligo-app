-- BliGO — Évolution vers un SIGB complet, Phase 1 : socle de traçabilité (17/09/2026)
-- Voir BliGo_note_cadrage_SIGB_rapport_annuel.pdf.
--
-- Deux briques indépendantes mais toutes deux "Phase 1" du document :
-- 1. Un journal d'activité générique (qui a fait quoi, quand, sur quel site),
--    posé sur les actions déjà réalisées dans BliGO aujourd'hui — la base dont
--    dépendent les statistiques et le futur module Neoscrib.
-- 2. Le compteur "+1 visiteur" (fréquentation, code E147 du rapport annuel),
--    recommandé en premier dans le document car simple et autonome.
--
-- Migration ADDITIVE. À exécuter dans Supabase : SQL Editor > New query > Run.


-- ============================================================
-- 1. Journal d'activité générique
-- ============================================================
-- entity_id en text (pas bigint) pour rester générique : les livres ont un id
-- numérique, les usagers un uuid, etc. Ce n'est qu'un journal de lecture, pas
-- une clé étrangère réelle.

create table public.activity_events (
  id bigint generated always as identity primary key,
  event_type text not null,
  occurred_at timestamptz not null default now(),
  commune_id bigint references public.communes(id),
  actor_id uuid references auth.users(id),
  entity_type text,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb
);

create index activity_events_type_idx on public.activity_events (event_type, occurred_at);
create index activity_events_commune_idx on public.activity_events (commune_id, occurred_at);

alter table public.activity_events enable row level security;

create policy "La direction consulte le journal d'activité"
  on public.activity_events for select
  using (public.is_direction());

-- Toujours appelée en interne (perform), jamais directement par le client :
-- security definer, pas de policy d'insertion nécessaire.
create or replace function public.log_activity(
  p_event_type text, p_commune_id bigint, p_entity_type text, p_entity_id text, p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.activity_events (event_type, commune_id, actor_id, entity_type, entity_id, metadata)
  values (p_event_type, p_commune_id, auth.uid(), p_entity_type, p_entity_id, p_metadata);
end;
$$;


-- ============================================================
-- 2. Notices et exemplaires (books, book_copies)
-- ============================================================

create or replace function public.trg_log_books()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.log_activity('book_created', new.commune_id, 'book', new.id::text,
      jsonb_build_object('title', new.title, 'category', new.category, 'isbn', new.isbn));
  elsif tg_op = 'UPDATE' then
    perform public.log_activity('book_updated', new.commune_id, 'book', new.id::text,
      jsonb_build_object('title', new.title));
  elsif tg_op = 'DELETE' then
    perform public.log_activity('book_deleted', old.commune_id, 'book', old.id::text,
      jsonb_build_object('title', old.title));
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_books_activity on public.books;
create trigger trg_books_activity
  after insert or update or delete on public.books
  for each row execute function public.trg_log_books();

create or replace function public.trg_log_book_copies()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.log_activity('copy_created', new.owner_commune_id, 'book_copy', new.id::text,
      jsonb_build_object('barcode', new.barcode, 'source', new.source, 'book_id', new.book_id));
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    perform public.log_activity('copy_status_changed', new.current_commune_id, 'book_copy', new.id::text,
      jsonb_build_object('from', old.status, 'to', new.status, 'book_id', new.book_id));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_book_copies_activity on public.book_copies;
create trigger trg_book_copies_activity
  after insert or update on public.book_copies
  for each row execute function public.trg_log_book_copies();


-- ============================================================
-- 3. Prêts (loans) : emprunt et retour
-- ============================================================

create or replace function public.trg_log_loans()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.log_activity('loan_created', new.borrowed_at_commune_id, 'loan', new.id::text,
      jsonb_build_object('copy_id', new.copy_id, 'user_id', new.user_id, 'from_reservation', new.reservation_id is not null));
  elsif tg_op = 'UPDATE' and new.returned_at is not null and old.returned_at is null then
    perform public.log_activity('loan_returned', new.returned_at_commune_id, 'loan', new.id::text,
      jsonb_build_object('copy_id', new.copy_id, 'was_late', new.returned_at > new.due_at));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_loans_activity on public.loans;
create trigger trg_loans_activity
  after insert or update on public.loans
  for each row execute function public.trg_log_loans();


-- ============================================================
-- 4. Réservations Click & Collect
-- ============================================================

create or replace function public.trg_log_reservations()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commune bigint;
begin
  select commune_id into v_commune from public.profiles where id = new.user_id;

  if tg_op = 'INSERT' then
    perform public.log_activity('reservation_created', v_commune, 'reservation', new.id::text,
      jsonb_build_object('book_id', new.book_id));
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    perform public.log_activity('reservation_status_changed', v_commune, 'reservation', new.id::text,
      jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reservations_activity on public.reservations;
create trigger trg_reservations_activity
  after insert or update on public.reservations
  for each row execute function public.trg_log_reservations();


-- ============================================================
-- 5. Usagers (profiles) : inscription, validation, catégorie tarifaire
-- ============================================================

create or replace function public.trg_log_profiles()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.log_activity('profile_created', new.commune_id, 'profile', new.id::text,
      jsonb_build_object('account_type', new.account_type));
  elsif tg_op = 'UPDATE' then
    if new.tariff_category is distinct from old.tariff_category then
      perform public.log_activity('tariff_category_changed', new.commune_id, 'profile', new.id::text,
        jsonb_build_object('from', old.tariff_category, 'to', new.tariff_category));
    end if;
    if new.commune_confirmed is distinct from old.commune_confirmed and new.commune_confirmed then
      perform public.log_activity('registration_validated', new.commune_id, 'profile', new.id::text,
        jsonb_build_object('subscriber_number', new.subscriber_number));
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profiles_activity on public.profiles;
create trigger trg_profiles_activity
  after insert or update on public.profiles
  for each row execute function public.trg_log_profiles();


-- ============================================================
-- 6. Agenda culturel (events)
-- ============================================================

create or replace function public.trg_log_events_table()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.log_activity('cultural_event_created', new.commune_id, 'event', new.id::text,
      jsonb_build_object('event_type', new.event_type, 'title', new.title));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_events_activity on public.events;
create trigger trg_events_activity
  after insert on public.events
  for each row execute function public.trg_log_events_table();


-- ============================================================
-- 7. Dons (donations)
-- ============================================================

create or replace function public.trg_log_donations()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.log_activity('donation_recorded', null, 'donation', new.id::text,
    jsonb_build_object('title', new.title, 'points', new.points_awarded));
  return new;
end;
$$;

drop trigger if exists trg_donations_activity on public.donations;
create trigger trg_donations_activity
  after insert on public.donations
  for each row execute function public.trg_log_donations();


-- ============================================================
-- 8. Compteur de fréquentation "+1 visiteur" (code E147)
-- ============================================================
-- Une entrée = date, heure, site, nombre de personnes (familles/groupes en une
-- seule action) et un motif facultatif et anonyme. Jamais de nom ni de numéro
-- de carte associé, conformément au document de cadrage.

create table public.visitor_entries (
  id bigint generated always as identity primary key,
  commune_id bigint not null references public.communes(id),
  occurred_at timestamptz not null default now(),
  count integer not null default 1 check (count > 0),
  motif text,
  recorded_by uuid references auth.users(id),
  corrected boolean not null default false,
  correction_reason text,
  created_at timestamptz not null default now()
);

create index visitor_entries_commune_date_idx on public.visitor_entries (commune_id, occurred_at);

alter table public.visitor_entries enable row level security;

create policy "Un agent ajoute des entrées visiteurs"
  on public.visitor_entries for insert
  with check (public.is_agent() or public.is_super_admin());

create policy "Un agent voit les entrées visiteurs"
  on public.visitor_entries for select
  using (public.is_agent() or public.is_super_admin());

-- La correction reste possible (ex. double-clic par erreur), mais on ne
-- supprime jamais silencieusement une entrée : une raison est enregistrée.
create policy "Un agent corrige une entrée visiteur"
  on public.visitor_entries for update
  using (public.is_agent() or public.is_super_admin())
  with check (public.is_agent() or public.is_super_admin());

create or replace function public.record_visitor_entry(p_count integer default 1, p_motif text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commune bigint;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  v_commune := public.agent_commune_id();
  if v_commune is null then
    raise exception 'Aucune médiathèque associée à ce compte agent';
  end if;

  insert into public.visitor_entries (commune_id, count, motif, recorded_by)
  values (v_commune, greatest(1, coalesce(p_count, 1)), p_motif, auth.uid());

  perform public.log_activity('visitor_entry', v_commune, 'visitor_entry', null,
    jsonb_build_object('count', greatest(1, coalesce(p_count, 1)), 'motif', p_motif));
end;
$$;

-- Total du jour pour la médiathèque de l'agent connecté, affiché dans
-- l'écran Emprunt/Retour.
create or replace function public.visitor_count_today()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(count), 0)::integer
  from public.visitor_entries
  where commune_id = public.agent_commune_id()
    and occurred_at::date = current_date;
$$;
