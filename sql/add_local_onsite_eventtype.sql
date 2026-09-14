-- BliGO — Trois ajouts rapides du retour terrain du 14/09/2026
-- 1. Catégorie "Fonds local" (auteurs/documents antillais et caribéens), en premier
-- 2. Consultation sur place vs emprunt, choisi au catalogage
-- 3. Type d'événement pour l'agenda culturel (Exposition, Débat...)
--
-- Prérequis : add_copies_communities_loans.sql, add_scan_operations.sql
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run


-- ============================================================
-- 1. Catégorie "Fonds local"
-- ============================================================

alter table public.books drop constraint if exists books_category_check;
alter table public.books add constraint books_category_check check (
  category is null or category in (
    'Fonds local', 'Roman', 'Thriller', 'Fantasy', 'Jeunesse', 'BD',
    'Bien-être', 'Maison', 'Histoire', 'Culture', 'Autres'
  )
);

alter table public.free_books drop constraint if exists free_books_category_check;
alter table public.free_books add constraint free_books_category_check check (
  category is null or category in (
    'Fonds local', 'Roman', 'Thriller', 'Fantasy', 'Jeunesse', 'BD',
    'Bien-être', 'Maison', 'Histoire', 'Culture', 'Autres'
  )
);


-- ============================================================
-- 2. Consultation sur place uniquement (non empruntable)
-- ============================================================
-- Décidé par l'agent au catalogage. Un livre "sur place" reste visible dans
-- le catalogue usager (pas masqué), juste non réservable/empruntable.

alter table public.books add column if not exists on_site_only boolean not null default false;

-- Bloque l'emprunt côté base, pas seulement côté interface : si scan_checkout
-- est appelé directement sur un exemplaire "sur place", on refuse proprement.
create or replace function public.scan_checkout(p_barcode text, p_subscriber_number text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_book public.books;
  v_user_id uuid;
  v_user_commune bigint;
  v_agent_commune bigint;
  v_scope text;
  v_duration integer;
  v_due timestamptz;
  v_reservation_id bigint;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_copy from public.book_copies where barcode = trim(p_barcode);
  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Code-barres inconnu.');
  end if;

  select * into v_book from public.books where id = v_copy.book_id;

  if v_book.on_site_only then
    return jsonb_build_object('ok', false,
      'message', 'Ce livre est en consultation sur place uniquement, il ne peut pas être emprunté.');
  end if;

  select id, commune_id into v_user_id, v_user_commune
  from public.profiles where subscriber_number = trim(p_subscriber_number);

  if v_user_id is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun usager ne porte ce numéro d''abonné.');
  end if;

  if v_copy.status = 'borrowed' then
    return jsonb_build_object('ok', false, 'message', 'Cet exemplaire est déjà emprunté.');
  end if;

  if v_copy.status in ('in_transit', 'processing', 'lost', 'withdrawn') then
    return jsonb_build_object('ok', false,
      'message', 'Cet exemplaire n''est pas empruntable pour le moment (' || v_copy.status || ').');
  end if;

  -- Réservation mise de côté : elle doit appartenir à l'usager qui se présente
  if v_copy.status = 'reserved' then
    select r.id into v_reservation_id
    from public.reservations r
    where r.book_id = v_copy.book_id
      and r.user_id = v_user_id
      and r.status in ('pret', 'preparation')
    order by r.created_at
    limit 1;

    if v_reservation_id is null then
      return jsonb_build_object('ok', false,
        'message', 'Cet exemplaire est mis de côté pour un autre usager.');
    end if;
  end if;

  -- Règle de prêt de la communauté de communes
  v_agent_commune := coalesce(public.agent_commune_id(), v_copy.current_commune_id);

  select co.lending_scope, co.loan_duration_days
  into v_scope, v_duration
  from public.communes cm
  join public.communities co on co.id = cm.community_id
  where cm.id = v_copy.current_commune_id;

  v_duration := coalesce(v_duration, 21);

  if v_scope = 'commune' and v_user_commune is distinct from v_copy.current_commune_id then
    return jsonb_build_object('ok', false,
      'message', 'Cet usager est inscrit dans une autre commune, et le contrat limite le prêt à la médiathèque de sa commune.');
  end if;

  v_due := now() + (v_duration || ' days')::interval;

  insert into public.loans (
    copy_id, user_id, reservation_id,
    borrowed_at_commune_id, due_at, borrowed_by_agent
  ) values (
    v_copy.id, v_user_id, v_reservation_id,
    v_copy.current_commune_id, v_due, auth.uid()
  );

  update public.book_copies set status = 'borrowed' where id = v_copy.id;

  -- La réservation Click & Collect est soldée par le passage au comptoir
  if v_reservation_id is not null then
    update public.reservations
      set status = 'recupere', return_due_at = v_due
      where id = v_reservation_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'title', v_book.title,
    'author', v_book.author,
    'due_at', v_due,
    'from_reservation', v_reservation_id is not null,
    'message', 'Emprunt enregistré, à rendre avant le ' || to_char(v_due, 'DD/MM/YYYY') || '.'
  );
end;
$$;


-- ============================================================
-- 3. Type d'événement (agenda culturel)
-- ============================================================

alter table public.events add column if not exists event_type text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'events_type_check'
  ) then
    alter table public.events add constraint events_type_check check (
      event_type is null or event_type in (
        'Club de lecture', 'Heure du conte', 'Atelier', 'Exposition', 'Débat', 'Autre'
      )
    );
  end if;
end $$;
