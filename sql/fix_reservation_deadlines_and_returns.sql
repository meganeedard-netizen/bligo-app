-- Corrige un vrai bug : le décompte "il vous reste Xh pour récupérer" se
-- déclenchait dès la réservation (statut "En préparation"), avant même que le
-- livre soit prêt. Le délai de 48h doit démarrer au moment où l'agent passe
-- la réservation à "Prêt", pas avant.
--
-- Ajoute aussi le suivi des retours pour le catalogue officiel : un livre
-- récupéré doit être rendu sous 3 semaines, avec rappel automatique. Les
-- livres hors condition n'ont eux aucune obligation de retour (rappel, s'ils
-- ne l'ont pas déjà : "sans obligation de le rapporter").

-- ============================================================
-- 1. Réservations du catalogue officiel
-- ============================================================
alter table public.reservations add column if not exists ready_at timestamptz;
alter table public.reservations add column if not exists return_due_at timestamptz;
alter table public.reservations add column if not exists return_reminded boolean not null default false;
alter table public.reservations add column if not exists reshelved boolean not null default false;

-- Fixe ready_at au passage à "prêt", et return_due_at (+21 jours) au passage
-- à "récupéré" — avec les notifications correspondantes.
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

-- Le délai de 48h (et le rappel à 24h) ne concerne désormais que les
-- réservations passées à "prêt", à partir de ready_at — jamais celles encore
-- "en préparation".
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

-- Rappel de retour, quelques jours avant l'échéance des 3 semaines.
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

-- ============================================================
-- 2. Livres hors condition (Bibliothèque Libre) — même correction du délai
-- ============================================================
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
