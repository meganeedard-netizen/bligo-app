-- BliGO — Relances de retour unifiées, avec vraie mise en file d'attente d'e-mail (14/09/2026)
-- Couvre les deux façons d'emprunter un livre chez BliGO :
--   - via une réservation Click & Collect (bouton "Marquer récupéré" côté agent,
--     ou scan_checkout quand la réservation était liée à un exemplaire)
--   - au comptoir sans réservation (scan_checkout), qui n'avait jusqu'ici
--     aucun rappel, ni in-app ni email
--
-- Remplace le cron existant "remind-upcoming-returns" (in-app seulement, ne
-- couvrait que les réservations) par une version qui couvre aussi les prêts
-- au comptoir, ajoute un rappel distinct une fois le livre en retard, et
-- met en file d'attente un vrai e-mail (table email_outbox) — l'envoi
-- effectif est fait par une Edge Function séparée, voir
-- supabase/functions/send-queued-emails.
--
-- Prérequis : add_copies_communities_loans.sql, add_scan_operations.sql
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run


-- ============================================================
-- 1. Colonnes manquantes
-- ============================================================

alter table public.reservations add column if not exists overdue_reminded boolean not null default false;
alter table public.loans add column if not exists return_reminded boolean not null default false;
alter table public.loans add column if not exists overdue_reminded boolean not null default false;


-- ============================================================
-- 2. File d'attente d'e-mails
-- ============================================================
-- Postgres ne sait pas envoyer un e-mail lui-même : cette table est juste une
-- boîte de dépôt, remplie ici, vidée par l'Edge Function send-queued-emails
-- (appelée par le même cron, voir section 4).

create table if not exists public.email_outbox (
  id bigint generated always as identity primary key,
  to_email text not null,
  to_name text,
  subject text not null,
  body_text text not null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  error text
);

create index if not exists email_outbox_unsent_idx on public.email_outbox (created_at) where sent_at is null;

alter table public.email_outbox enable row level security;
-- Aucune policy select/insert/update pour les rôles normaux : uniquement
-- accessible via service_role (l'Edge Function), jamais depuis le navigateur.


-- ============================================================
-- 3. Détection unifiée + mise en file
-- ============================================================
-- Un rappel "bientôt à rendre" (3 jours avant l'échéance, une seule fois),
-- puis un rappel distinct "en retard" (dès que l'échéance est dépassée, une
-- seule fois aussi). Toujours in-app + email en même temps.

create or replace function public.queue_return_reminders()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_name text;
  v_title text;
  v_due timestamptz;
  rec record;
begin
  -- ---------- Bientôt à rendre (J-3) ----------
  for rec in
    select r.id, r.user_id, b.title, r.return_due_at as due_at, 'reservation'::text as source
    from public.reservations r
    join public.books b on b.id = r.book_id
    where r.status = 'recupere'
      and r.return_due_at is not null
      and r.return_reminded = false
      and r.return_due_at <= now() + interval '3 days'
      and r.return_due_at > now()
    union all
    select l.id, l.user_id, b.title, l.due_at, 'loan'
    from public.loans l
    join public.book_copies bc on bc.id = l.copy_id
    join public.books b on b.id = bc.book_id
    where l.returned_at is null
      and l.reservation_id is null -- déjà couvert par la branche reservations ci-dessus
      and l.return_reminded = false
      and l.due_at <= now() + interval '3 days'
      and l.due_at > now()
  loop
    select p.full_name, u.email into v_name, v_email
    from public.profiles p join auth.users u on u.id = p.id
    where p.id = rec.user_id;

    insert into public.notifications (user_id, message)
    values (rec.user_id, 'Pense à rapporter « ' || rec.title || ' » à la médiathèque avant le ' || to_char(rec.due_at, 'DD/MM/YYYY') || '.');

    if v_email is not null then
      insert into public.email_outbox (to_email, to_name, subject, body_text)
      values (
        v_email, v_name,
        'À rendre bientôt : ' || rec.title,
        'Bonjour ' || coalesce(v_name, '') || E',\n\n' ||
        'Petit rappel : « ' || rec.title || ' » est à rapporter à ta médiathèque avant le ' || to_char(rec.due_at, 'DD/MM/YYYY') || E'.\n\n' ||
        E'À bientôt,\nL''équipe BliGO'
      );
    end if;

    if rec.source = 'reservation' then
      update public.reservations set return_reminded = true where id = rec.id;
    else
      update public.loans set return_reminded = true where id = rec.id;
    end if;
  end loop;

  -- ---------- En retard ----------
  for rec in
    select r.id, r.user_id, b.title, r.return_due_at as due_at, 'reservation'::text as source
    from public.reservations r
    join public.books b on b.id = r.book_id
    where r.status = 'recupere'
      and r.return_due_at is not null
      and r.overdue_reminded = false
      and r.return_due_at <= now()
    union all
    select l.id, l.user_id, b.title, l.due_at, 'loan'
    from public.loans l
    join public.book_copies bc on bc.id = l.copy_id
    join public.books b on b.id = bc.book_id
    where l.returned_at is null
      and l.reservation_id is null
      and l.overdue_reminded = false
      and l.due_at <= now()
  loop
    select p.full_name, u.email into v_name, v_email
    from public.profiles p join auth.users u on u.id = p.id
    where p.id = rec.user_id;

    insert into public.notifications (user_id, message)
    values (rec.user_id, '« ' || rec.title || ' » est en retard, pense à le rapporter dès que possible.');

    if v_email is not null then
      insert into public.email_outbox (to_email, to_name, subject, body_text)
      values (
        v_email, v_name,
        'En retard : ' || rec.title,
        'Bonjour ' || coalesce(v_name, '') || E',\n\n' ||
        '« ' || rec.title || ' » était à rapporter avant le ' || to_char(rec.due_at, 'DD/MM/YYYY') || E', pense à le rapporter dès que possible à ta médiathèque.\n\n' ||
        E'À bientôt,\nL''équipe BliGO'
      );
    end if;

    if rec.source = 'reservation' then
      update public.reservations set overdue_reminded = true where id = rec.id;
    else
      update public.loans set overdue_reminded = true where id = rec.id;
    end if;
  end loop;
end;
$$;


-- ============================================================
-- 4. Remplace l'ancien cron (in-app seulement, réservations uniquement)
-- ============================================================

select cron.unschedule('remind-upcoming-returns');

select cron.schedule('queue-return-reminders', '0 9 * * *', $$select public.queue_return_reminders();$$);

-- Envoi effectif des e-mails en attente, quelques minutes plus tard (laisse
-- le temps à la file de se remplir avant que l'Edge Function ne la vide).
-- L'URL et la clé sont à compléter une fois l'Edge Function déployée, voir
-- le README à côté de supabase/functions/send-queued-emails.
select cron.schedule(
  'send-queued-emails',
  '10 9 * * *',
  $$
  select net.http_post(
    url := 'https://knlymrujmiapzieavzoe.supabase.co/functions/v1/send-queued-emails',
    headers := jsonb_build_object('Authorization', 'Bearer REMPLACER_PAR_LA_CLE_SERVICE_ROLE', 'Content-Type', 'application/json'),
    body := '{}'::jsonb
  );
  $$
);
