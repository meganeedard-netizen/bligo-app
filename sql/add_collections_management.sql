-- Gestion des collections (09/10/2026) : prix, désherbage, documents perdus
-- ou abîmés, bulletinage des magazines
-- ============================================================
-- Demandes de Mégane du 09/10/2026 :
--   - prix des documents repris de la BnF (010 $d) et des API au catalogage ;
--   - désherbage : motif IOUPI, destination (don, pilon, vente, autre
--     structure), en série, avec liste de candidats et statistiques ;
--   - documents perdus ou abîmés : une « dette » au prix du document, en
--     rouge au scan de la carte, emprunts et réservations bloqués tant
--     qu'elle n'est pas réglée, annulée si le livre revient, présomption de
--     perte après X jours de retard, export des impayés pour la régie ;
--   - bulletinage : abonnements de la médiathèque, numéros attendus, retards,
--     avec un catalogue de magazines courants (ISSN vérifiés à la BnF le
--     09/10/2026) pour démarrer vite.
-- À exécuter APRÈS add_family_and_digital.sql.


-- ============================================================
-- 1. Prix des documents
-- ============================================================
alter table public.books add column if not exists price_cents integer;


-- ============================================================
-- 2. Désherbage
-- ============================================================
alter table public.book_copies add column if not exists withdrawn_reason text
  check (withdrawn_reason is null or withdrawn_reason in ('incorrect', 'ordinaire', 'use', 'perime', 'inadequat', 'autre'));
alter table public.book_copies add column if not exists withdrawn_destination text
  check (withdrawn_destination is null or withdrawn_destination in ('don', 'pilon', 'vente', 'autre_structure', 'autre'));
alter table public.book_copies add column if not exists withdrawn_at timestamptz;
alter table public.book_copies add column if not exists withdrawn_by uuid references auth.users(id);
alter table public.books add column if not exists archived boolean not null default false;

create or replace function public.weed_copies(p_copy_ids bigint[], p_reason text, p_destination text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_archived integer;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  if exists (select 1 from public.book_copies where id = any(p_copy_ids) and status in ('borrowed', 'reserved', 'in_transit')) then
    return jsonb_build_object('ok', false, 'message', 'Un exemplaire de la liste est emprunté, mis de côté ou en transit : retire-le de la liste.');
  end if;

  update public.book_copies
    set status = 'withdrawn', withdrawn_reason = p_reason, withdrawn_destination = p_destination,
        withdrawn_at = now(), withdrawn_by = auth.uid()
    where id = any(p_copy_ids) and status <> 'withdrawn';
  get diagnostics v_count = row_count;

  -- Plus aucun exemplaire en service : la fiche sort du catalogue usager.
  update public.books b set archived = true, available = false
    where b.id in (select book_id from public.book_copies where id = any(p_copy_ids))
      and not exists (select 1 from public.book_copies c where c.book_id = b.id and c.status not in ('withdrawn', 'lost'));
  get diagnostics v_archived = row_count;

  return jsonb_build_object('ok', true, 'count', v_count, 'archived', v_archived,
    'message', v_count || ' exemplaire(s) retiré(s) du fonds' ||
      case when v_archived > 0 then ', ' || v_archived || ' fiche(s) retirée(s) du catalogue.' else '.' end);
end;
$$;

-- Candidats : exemplaires disponibles pas empruntés depuis p_years ans (ou
-- jamais, et acquis depuis plus longtemps que ça).
create or replace function public.weeding_candidates(p_years integer default 3)
returns table (copy_id bigint, barcode text, title text, author text, cote text, last_loan_at timestamptz, acquired_at date)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.barcode, b.title, b.author, coalesce(c.shelf_location, b.shelf_location),
         (select max(l.borrowed_at) from public.loans l where l.copy_id = c.id), c.acquired_at
  from public.book_copies c join public.books b on b.id = c.book_id
  where c.status = 'available'
    and (public.agent_commune_id() is null or c.current_commune_id = public.agent_commune_id())
    and coalesce((select max(l.borrowed_at) from public.loans l where l.copy_id = c.id), c.acquired_at::timestamptz)
        < now() - make_interval(years => greatest(1, p_years))
  order by 6 nulls first, 7
  limit 200;
$$;

create or replace function public.weeding_stats(p_year integer)
returns table (reason text, destination text, copies bigint)
language sql
stable
security definer
set search_path = public
as $$
  select withdrawn_reason, withdrawn_destination, count(*)
  from public.book_copies
  where status = 'withdrawn' and extract(year from withdrawn_at) = p_year
    and (public.agent_commune_id() is null or current_commune_id = public.agent_commune_id())
  group by 1, 2 order by 3 desc;
$$;


-- ============================================================
-- 3. Documents perdus ou abîmés
-- ============================================================
alter table public.communes add column if not exists presumed_lost_days integer default 60;
alter table public.communes add column if not exists lost_default_fee_cents integer not null default 1500;
alter table public.loans add column if not exists lost boolean not null default false;

create table if not exists public.document_debts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id bigint references public.books(id) on delete set null,
  copy_id bigint references public.book_copies(id) on delete set null,
  loan_id bigint references public.loans(id) on delete set null,
  commune_id bigint references public.communes(id),
  kind text not null check (kind in ('perdu', 'abime')),
  amount_cents integer not null default 0,
  status text not null default 'open' check (status in ('open', 'paid', 'replaced', 'returned', 'cancelled')),
  automatic boolean not null default false,
  note text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  settled_at timestamptz,
  settled_by uuid references auth.users(id)
);
create index if not exists document_debts_open_idx on public.document_debts (user_id) where status = 'open';

alter table public.document_debts enable row level security;
drop policy if exists "Un usager voit ses dettes" on public.document_debts;
create policy "Un usager voit ses dettes"
  on public.document_debts for select
  using (auth.uid() = user_id or public.is_agent() or public.is_super_admin());

create or replace function public.has_open_debt(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.document_debts where user_id = p_user_id and status = 'open');
$$;

create or replace function public.update_commune_debt_settings(p_commune_id bigint, p_presumed_lost_days integer, p_default_fee_cents integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;
  update public.communes
    set presumed_lost_days = case when coalesce(p_presumed_lost_days, 0) > 0 then p_presumed_lost_days else null end,
        lost_default_fee_cents = greatest(0, coalesce(p_default_fee_cents, 1500))
    where id = p_commune_id;
end;
$$;

-- Perte : le prêt est clôturé, l'exemplaire passe « perdu », une dette au
-- prix du document (ou au forfait de la médiathèque) est ouverte.
create or replace function public.declare_lost_internal(p_loan_id bigint, p_amount_cents integer, p_automatic boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.loans;
  v_book public.books;
  v_copy public.book_copies;
  v_amount integer;
begin
  select * into v_loan from public.loans where id = p_loan_id and returned_at is null;
  if v_loan.id is null then
    return jsonb_build_object('ok', false, 'message', 'Prêt introuvable ou déjà rendu.');
  end if;
  select * into v_copy from public.book_copies where id = v_loan.copy_id;
  select * into v_book from public.books where id = v_copy.book_id;
  v_amount := coalesce(p_amount_cents, v_book.price_cents,
    (select lost_default_fee_cents from public.communes where id = v_loan.borrowed_at_commune_id), 1500);

  update public.loans set returned_at = now(), lost = true, returned_by_agent = auth.uid() where id = v_loan.id;
  update public.book_copies set status = 'lost' where id = v_copy.id;
  if v_loan.reservation_id is not null then
    update public.reservations set status = 'expiree', reshelved = true where id = v_loan.reservation_id;
  end if;

  insert into public.document_debts (user_id, book_id, copy_id, loan_id, commune_id, kind, amount_cents, automatic, created_by)
  values (v_loan.user_id, v_book.id, v_copy.id, v_loan.id, v_loan.borrowed_at_commune_id, 'perdu', v_amount, p_automatic, auth.uid());

  insert into public.notifications (user_id, message)
  values (v_loan.user_id, '« ' || coalesce(v_book.title, '') || ' » est considéré comme perdu. Rapporte-le, remplace-le à l''identique ou règle ' ||
    to_char(v_amount / 100.0, 'FM999990.00') || ' € à la médiathèque. En attendant, les emprunts sont suspendus.');

  return jsonb_build_object('ok', true, 'amount_cents', v_amount,
    'message', 'Document déclaré perdu : ' || to_char(v_amount / 100.0, 'FM999990.00') || ' € à régler (ou remplacement à l''identique).');
end;
$$;

create or replace function public.declare_lost(p_loan_id bigint, p_amount_cents integer default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  return public.declare_lost_internal(p_loan_id, p_amount_cents, false);
end;
$$;

-- Document rendu abîmé : dette sans clôturer quoi que ce soit (le retour a
-- déjà été enregistré).
create or replace function public.declare_damaged(p_copy_id bigint, p_amount_cents integer default null, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.loans;
  v_book public.books;
  v_amount integer;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  select * into v_loan from public.loans where copy_id = p_copy_id order by borrowed_at desc limit 1;
  if v_loan.id is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun emprunt connu pour cet exemplaire.');
  end if;
  select b.* into v_book from public.books b join public.book_copies c on c.book_id = b.id where c.id = p_copy_id;
  v_amount := coalesce(p_amount_cents, v_book.price_cents,
    (select lost_default_fee_cents from public.communes where id = v_loan.borrowed_at_commune_id), 1500);
  insert into public.document_debts (user_id, book_id, copy_id, loan_id, commune_id, kind, amount_cents, note, created_by)
  values (v_loan.user_id, v_book.id, p_copy_id, v_loan.id, v_loan.borrowed_at_commune_id, 'abime', v_amount, p_note, auth.uid());
  insert into public.notifications (user_id, message)
  values (v_loan.user_id, '« ' || coalesce(v_book.title, '') || ' » a été rendu abîmé. Remplace-le à l''identique ou règle ' ||
    to_char(v_amount / 100.0, 'FM999990.00') || ' € à la médiathèque. En attendant, les emprunts sont suspendus.');
  return jsonb_build_object('ok', true, 'message', 'Dette enregistrée : ' || to_char(v_amount / 100.0, 'FM999990.00') || ' € (ou remplacement à l''identique).');
end;
$$;

create or replace function public.settle_debt(p_debt_id bigint, p_status text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  if p_status not in ('paid', 'replaced', 'cancelled') then
    raise exception 'Statut invalide';
  end if;
  update public.document_debts
    set status = p_status, settled_at = now(), settled_by = auth.uid(), note = coalesce(p_note, note)
    where id = p_debt_id and status = 'open';
  return jsonb_build_object('ok', true);
end;
$$;

-- Le livre « perdu » revient finalement (scan de retour) : la dette tombe.
create or replace function public.trg_cancel_debt_on_found()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'lost' and new.status = 'available' then
    update public.document_debts set status = 'returned', settled_at = now(), settled_by = auth.uid()
      where copy_id = new.id and kind = 'perdu' and status = 'open';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cancel_debt_on_found on public.book_copies;
create trigger trg_cancel_debt_on_found
  after update of status on public.book_copies
  for each row execute function public.trg_cancel_debt_on_found();

-- Présomption de perte (cron quotidien) : retard au-delà du délai de la
-- médiathèque (presumed_lost_days, null = désactivé).
create or replace function public.mark_presumed_lost()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select l.id from public.loans l join public.communes c on c.id = l.borrowed_at_commune_id
    where l.returned_at is null and c.presumed_lost_days is not null
      and l.due_at < now() - make_interval(days => c.presumed_lost_days)
  loop
    perform public.declare_lost_internal(r.id, null, true);
    n := n + 1;
  end loop;
  return n;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'mark-presumed-lost';
    perform cron.schedule('mark-presumed-lost', '30 9 * * *', 'select public.mark_presumed_lost()');
  end if;
end $$;

-- Blocage des emprunts et réservations tant qu'une dette est ouverte
-- (reprend scan_checkout et check_reservation_membership à l'identique).
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
  v_user_flagged boolean;
  v_user_tariff_category text;
  v_reservation_id bigint;
  v_membership text;
  v_duration integer;
  v_due timestamptz;
  v_agent_commune bigint;
  v_restricted_categories text[];
  v_blocks_new_release boolean;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_copy from public.book_copies where barcode = trim(p_barcode);
  if v_copy.id is null then
    return jsonb_build_object('ok', false, 'message', 'Code-barres inconnu.');
  end if;

  select * into v_book from public.books where id = v_copy.book_id;

  select id, commune_id, coalesce(flagged, false), tariff_category
  into v_user_id, v_user_commune, v_user_flagged, v_user_tariff_category
  from public.profiles where subscriber_number = trim(p_subscriber_number);

  if v_user_id is null then
    return jsonb_build_object('ok', false, 'message', 'Aucun usager ne porte ce numéro d''abonné.');
  end if;

  if v_user_tariff_category = 'mineur' and coalesce(v_book.adult_only, false) then
    return jsonb_build_object('ok', false, 'message', 'Ce livre est réservé aux comptes majeurs.');
  end if;

  if v_copy.status = 'borrowed' then
    return jsonb_build_object('ok', false, 'message', 'Cet exemplaire est déjà emprunté.');
  end if;

  if v_copy.status in ('in_transit', 'processing', 'lost', 'withdrawn') then
    return jsonb_build_object('ok', false,
      'message', 'Cet exemplaire n''est pas empruntable pour le moment (' || v_copy.status || ').');
  end if;

  select coalesce(flagged_restricted_categories, '{}'), coalesce(flagged_blocks_new_releases, true)
  into v_restricted_categories, v_blocks_new_release
  from public.communes where id = v_user_commune;

  if v_user_flagged and v_book.category = any(coalesce(v_restricted_categories, '{}')) then
    return jsonb_build_object('ok', false,
      'message', 'Cet usager est actuellement restreint et ne peut pas emprunter dans la catégorie « ' || v_book.category || ' ».');
  end if;

  if v_user_flagged and coalesce(v_blocks_new_release, true) and coalesce(v_book.is_new_release, false) then
    return jsonb_build_object('ok', false, 'message', 'Cet usager est actuellement restreint et ne peut pas emprunter les nouveautés.');
  end if;

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

  v_agent_commune := coalesce(public.agent_commune_id(), v_copy.current_commune_id);

  if public.has_open_debt(v_user_id) then
    return jsonb_build_object('ok', false, 'message', 'Cet usager a un document perdu ou abîmé non réglé : voir sa fiche avant tout nouvel emprunt.');
  end if;

  v_membership := public.membership_status(v_user_id, v_copy.current_commune_id);
  if v_membership <> 'ok' then
    return jsonb_build_object('ok', false, 'message', public.membership_error_message(v_membership));
  end if;

  if v_user_tariff_category = 'famille' and public.family_quota_reached(v_user_id) then
    return jsonb_build_object('ok', false, 'message', 'Le quota de la carte famille est atteint : un document doit être rendu avant un nouvel emprunt.');
  end if;

  v_duration := public.effective_loan_duration_days(v_book.id, v_copy.current_commune_id);
  v_due := now() + (v_duration || ' days')::interval;

  insert into public.loans (
    copy_id, user_id, reservation_id,
    borrowed_at_commune_id, due_at, borrowed_by_agent
  ) values (
    v_copy.id, v_user_id, v_reservation_id,
    v_copy.current_commune_id, v_due, auth.uid()
  );

  update public.book_copies set status = 'borrowed' where id = v_copy.id;

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

create or replace function public.check_reservation_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_commune bigint;
begin
  v_commune := coalesce(new.pickup_commune_id, (select commune_id from public.books where id = new.book_id));
  v_status := public.membership_status(new.user_id, v_commune);
  if v_status <> 'ok' then
    raise exception '%', public.membership_error_message(v_status);
  end if;
  if public.has_open_debt(new.user_id) then
    raise exception 'Un document perdu ou abîmé n''est pas réglé : rapproche-toi de la médiathèque avant de réserver.';
  end if;
  return new;
end;
$$;


-- ============================================================
-- 4. Bulletinage des magazines
-- ============================================================
create table if not exists public.periodical_catalog (
  issn text primary key,
  title text not null,
  publisher text,
  frequency text not null
);

create table if not exists public.periodical_subscriptions (
  id bigint generated always as identity primary key,
  commune_id bigint not null references public.communes(id) on delete cascade,
  title text not null,
  issn text,
  publisher text,
  frequency text not null default 'mensuel'
    check (frequency in ('quotidien', 'hebdomadaire', 'bimensuel', 'mensuel', 'bimestriel', 'trimestriel', 'semestriel', 'annuel', 'irregulier')),
  tolerance_days integer not null default 7,
  last_issue text,
  last_received_at timestamptz,
  next_expected_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (commune_id, issn)
);

alter table public.periodical_catalog enable row level security;
drop policy if exists "Catalogue de magazines public" on public.periodical_catalog;
create policy "Catalogue de magazines public" on public.periodical_catalog for select using (true);

alter table public.periodical_subscriptions enable row level security;
drop policy if exists "Abonnements visibles" on public.periodical_subscriptions;
create policy "Abonnements visibles" on public.periodical_subscriptions for select using (true);
drop policy if exists "Les agents gèrent les abonnements de leur médiathèque" on public.periodical_subscriptions;
create policy "Les agents gèrent les abonnements de leur médiathèque"
  on public.periodical_subscriptions for all
  using (public.is_super_admin() or (public.is_agent() and commune_id = public.agent_commune_id()))
  with check (public.is_super_admin() or (public.is_agent() and commune_id = public.agent_commune_id()));

create or replace function public.frequency_interval(p_frequency text)
returns interval
language sql
immutable
as $$
  select case p_frequency
    when 'quotidien' then interval '1 day'
    when 'hebdomadaire' then interval '7 days'
    when 'bimensuel' then interval '14 days'
    when 'mensuel' then interval '1 month'
    when 'bimestriel' then interval '2 months'
    when 'trimestriel' then interval '3 months'
    when 'semestriel' then interval '6 months'
    when 'annuel' then interval '1 year'
    else null
  end;
$$;

-- Réception d'un numéro : date de réception et prochain numéro attendu.
create or replace function public.receive_issue(p_subscription_id bigint, p_issue text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub public.periodical_subscriptions;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  select * into v_sub from public.periodical_subscriptions where id = p_subscription_id;
  if v_sub.id is null then
    return jsonb_build_object('ok', false, 'message', 'Abonnement introuvable.');
  end if;
  update public.periodical_subscriptions
    set last_issue = coalesce(nullif(trim(p_issue), ''), last_issue), last_received_at = now(),
        next_expected_at = now() + public.frequency_interval(frequency)
    where id = v_sub.id;
  return jsonb_build_object('ok', true, 'message', 'Numéro reçu' || coalesce(' (' || nullif(trim(p_issue), '') || ')', '') || ' pour ' || v_sub.title || '.');
end;
$$;

-- Appelée au catalogage d'un magazine : enregistre la réception si la
-- médiathèque est abonnée à cet ISSN.
create or replace function public.receive_issue_by_issn(p_issn text, p_issue text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  select id into v_id from public.periodical_subscriptions
  where issn = p_issn and active and commune_id = public.agent_commune_id() limit 1;
  if v_id is null then
    return jsonb_build_object('ok', false);
  end if;
  return public.receive_issue(v_id, p_issue);
end;
$$;

insert into public.periodical_catalog (title, issn, publisher, frequency) values
  ('Le Monde diplomatique', '0026-9395', 'Le Monde diplomatique', 'mensuel'),
  ('Télérama', '0040-2699', 'Télérama', 'hebdomadaire'),
  ('Elle', '0013-6298', 'Elle', 'hebdomadaire'),
  ('Science & Vie Junior', '0992-5899', 'Reworld Media', 'mensuel'),
  ('Astrapi', '0220-1186', 'Bayard Presse', 'bimensuel'),
  ('Wapiti', '0984-2314', 'Milan', 'mensuel'),
  ('Mon Quotidien', '1258-6447', 'Play Bac Presse', 'quotidien'),
  ('Le Petit Quotidien', '1288-6947', 'Play Bac Presse', 'quotidien'),
  ('L''Express', '0014-5270', 'L''Express', 'hebdomadaire'),
  ('Le Point', '0242-6005', 'Le Point', 'hebdomadaire'),
  ('Courrier international', '1154-516X', 'Courrier international', 'hebdomadaire'),
  ('Marie Claire', '0025-3049', 'Marie Claire', 'mensuel'),
  ('Ça m''intéresse', '0243-1335', 'Prisma Media', 'mensuel'),
  ('Historia', '1270-0835', 'Sophia Publications', 'mensuel'),
  ('L''Histoire', '0182-2411', 'Sophia Publications', 'mensuel'),
  ('Sciences Humaines', '0996-6994', 'Éditions Sciences Humaines', 'mensuel'),
  ('Paris Match', '0397-1635', 'Paris Match', 'hebdomadaire'),
  ('Femme Actuelle', '0764-0021', 'Prisma Media', 'hebdomadaire'),
  ('Spirou', '0771-8071', 'Dupuis', 'hebdomadaire'),
  ('Phosphore', '0249-8138', 'Bayard Presse', 'mensuel'),
  ('La Recherche', '0029-5671', 'Sophia Publications', 'mensuel'),
  ('Pour la Science', '0153-4092', 'Pour la Science', 'mensuel'),
  ('Marianne', '2491-5769', 'Marianne SA', 'hebdomadaire'),
  ('Mieux vivre votre argent', '1291-2549', 'Valmonde et Cie', 'mensuel'),
  ('Prima', '0293-2407', 'Prisma Media', 'mensuel'),
  ('Les Inrockuptibles', '0298-3788', 'Les Éditions indépendantes', 'mensuel'),
  ('Le 1', '2272-9690', 'FGH Invest', 'hebdomadaire'),
  ('Society', '2426-5780', 'So Press', 'bimensuel'),
  ('So Foot', '1765-9086', 'So Press', 'mensuel'),
  ('La Hulotte', '0337-2154', 'La Hulotte', 'irregulier'),
  ('Rock & Folk', '0750-7852', 'Éditions Larivière', 'mensuel'),
  ('Parents', '0553-2159', 'Uni-médias', 'bimestriel')
on conflict (issn) do nothing;

grant execute on function public.weed_copies(bigint[], text, text) to authenticated;
grant execute on function public.weeding_candidates(integer) to authenticated;
grant execute on function public.weeding_stats(integer) to authenticated;
grant execute on function public.has_open_debt(uuid) to authenticated;
grant execute on function public.update_commune_debt_settings(bigint, integer, integer) to authenticated;
grant execute on function public.declare_lost(bigint, integer) to authenticated;
grant execute on function public.declare_damaged(bigint, integer, text) to authenticated;
grant execute on function public.settle_debt(bigint, text, text) to authenticated;
grant execute on function public.receive_issue(bigint, text) to authenticated;
grant execute on function public.receive_issue_by_issn(text, text) to authenticated;
revoke execute on function public.declare_lost_internal(bigint, integer, boolean) from public, anon, authenticated;

-- ============================================================
-- 5. Récolement (validé par Mégane le 09/10/2026)
-- ============================================================
-- L'agent choisit une zone (déduite des cotes : « R » pour les romans, une
-- classe Dewey « 7.. » pour les arts, ou tout le fonds), scanne les livres
-- en rayon un par un, puis obtient : les manquants (attendus en rayon, pas
-- scannés), les mal rangés (scannés, mais leur cote n'est pas de la zone) et
-- ceux trouvés en rayon alors qu'ils sont notés empruntés.
create table if not exists public.inventories (
  id bigint generated always as identity primary key,
  commune_id bigint not null references public.communes(id) on delete cascade,
  zone text not null default '',
  zone_label text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  missing_count integer,
  misplaced_count integer,
  scanned_count integer,
  created_by uuid references auth.users(id)
);

create table if not exists public.inventory_scans (
  inventory_id bigint not null references public.inventories(id) on delete cascade,
  copy_id bigint not null references public.book_copies(id) on delete cascade,
  scanned_at timestamptz not null default now(),
  primary key (inventory_id, copy_id)
);

alter table public.inventories enable row level security;
alter table public.inventory_scans enable row level security;
drop policy if exists "Les agents gèrent les récolements" on public.inventories;
create policy "Les agents gèrent les récolements" on public.inventories for all
  using (public.is_super_admin() or (public.is_agent() and commune_id = public.agent_commune_id()))
  with check (public.is_super_admin() or (public.is_agent() and commune_id = public.agent_commune_id()));
drop policy if exists "Les agents gèrent les scans de récolement" on public.inventory_scans;
create policy "Les agents gèrent les scans de récolement" on public.inventory_scans for all
  using (public.is_agent() or public.is_super_admin())
  with check (public.is_agent() or public.is_super_admin());

-- La cote appartient-elle à la zone ? « » = tout le fonds ; « dewey:7 » =
-- classe Dewey 700 ; sinon le premier élément de la cote (« R », « J »…).
create or replace function public.cote_in_zone(p_cote text, p_zone text)
returns boolean
language sql
immutable
as $$
  select case
    when coalesce(p_zone, '') = '' then true
    when p_zone like 'dewey:%' then split_part(coalesce(p_cote, ''), ' ', 1) ~ ('^' || substr(p_zone, 7) || '[0-9]')
    else upper(split_part(coalesce(p_cote, ''), ' ', 1)) = upper(p_zone)
  end;
$$;

create or replace function public.inventory_report(p_inventory_id bigint)
returns table (section text, copy_id bigint, barcode text, title text, cote text, status text)
language sql
stable
security definer
set search_path = public
as $$
  with inv as (select * from public.inventories where id = p_inventory_id),
  copies as (
    select c.id, c.barcode, b.title, coalesce(c.shelf_location, b.shelf_location) as cote, c.status
    from public.book_copies c join public.books b on b.id = c.book_id, inv
    where c.current_commune_id = inv.commune_id
  ),
  scanned as (select copy_id from public.inventory_scans where inventory_id = p_inventory_id)
  select 'manquant', c.id, c.barcode, c.title, c.cote, c.status from copies c, inv
    where c.status = 'available' and public.cote_in_zone(c.cote, inv.zone) and c.id not in (select copy_id from scanned)
  union all
  select 'mal_range', c.id, c.barcode, c.title, c.cote, c.status from copies c, inv
    where c.id in (select copy_id from scanned) and not public.cote_in_zone(c.cote, inv.zone)
  union all
  select 'statut_a_verifier', c.id, c.barcode, c.title, c.cote, c.status from copies c
    where c.id in (select copy_id from scanned) and c.status in ('borrowed', 'lost', 'withdrawn', 'in_transit')
  order by 1, 5;
$$;

create or replace function public.finish_inventory(p_inventory_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_missing integer; v_misplaced integer; v_scanned integer;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  select count(*) filter (where section = 'manquant'), count(*) filter (where section = 'mal_range')
    into v_missing, v_misplaced from public.inventory_report(p_inventory_id);
  select count(*) into v_scanned from public.inventory_scans where inventory_id = p_inventory_id;
  update public.inventories set finished_at = now(), missing_count = v_missing, misplaced_count = v_misplaced, scanned_count = v_scanned
    where id = p_inventory_id;
  return jsonb_build_object('ok', true, 'missing', v_missing, 'misplaced', v_misplaced, 'scanned', v_scanned);
end;
$$;

-- Manquants confirmés après vérification : exemplaires passés « perdus »
-- (sans usager à facturer).
create or replace function public.mark_inventory_missing_lost(p_inventory_id bigint)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  update public.book_copies set status = 'lost'
    where id in (select copy_id from public.inventory_report(p_inventory_id) where section = 'manquant');
  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function public.inventory_report(bigint) to authenticated;
grant execute on function public.finish_inventory(bigint) to authenticated;
grant execute on function public.mark_inventory_missing_lost(bigint) to authenticated;


-- ============================================================
-- 6. Jeux de société (09/10/2026)
-- ============================================================
-- Catégorie « Jeux » (icône fournie par Mégane) et champs propres aux jeux.
alter table public.books add column if not exists players text;        -- ex. « 2 à 6 joueurs »
alter table public.books add column if not exists play_duration text;  -- ex. « 15 min »

alter table public.books drop constraint if exists books_category_check;
alter table public.books add constraint books_category_check check (
  category is null or category in (
    'Fonds local', 'Roman', 'Thriller', 'Fantasy', 'Jeunesse', 'BD',
    'Poésie & théâtre', 'Documentaire', 'Sciences & nature', 'Voyages', 'Sports & loisirs',
    'Bien-être', 'Maison', 'Histoire', 'Culture', 'Jeux', 'Autres'
  )
);
