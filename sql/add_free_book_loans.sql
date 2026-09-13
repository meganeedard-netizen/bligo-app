-- Aligne le parcours des livres hors condition (Bibliothèque Libre) sur celui
-- du Click & Collect officiel : statut (en préparation / prêt / récupéré /
-- expiré), délai de 48h avec rappel à 24h, et notifications identiques.

-- 1. Historique des emprunts hors condition (un livre = un emprunt à la fois,
-- comme une réservation officielle).
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

-- 2. "Prendre ce livre" crée maintenant un emprunt en statut "En préparation"
-- (comme une réservation), en plus des points/badges déjà en place.
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

-- 3. Notification "prêt à récupérer" (identique au Click & Collect officiel).
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

-- 4. Expiration automatique sous 48h (avec rappel à 24h) : le livre redevient
-- disponible pour quelqu'un d'autre si personne ne vient le récupérer,
-- exactement comme une réservation officielle non retirée.
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
