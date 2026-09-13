-- Empêche de réserver un livre qu'on a déjà en cours (réservé ou emprunté et
-- pas encore rendu) — bug observé : le catalogue laissait réserver une
-- deuxième fois un livre déjà emprunté (encore dans les 3 semaines de prêt),
-- créant deux réservations pour le même livre en même temps. Corrigé côté
-- interface (accueil.html), et bloqué ici aussi côté base de données pour
-- que ce ne soit pas contournable.
create or replace function public.enforce_reservation_limits()
returns trigger
language plpgsql
security definer
as $$
declare
  v_category text;
  v_is_jeunesse boolean;
  v_active_count integer;
  v_duplicate_count integer;
begin
  if tg_table_name = 'reservations' then
    select count(*) into v_duplicate_count
    from public.reservations r
    where r.user_id = new.user_id
      and r.book_id = new.book_id
      and (
        r.status in ('preparation', 'pret')
        or (r.status = 'recupere' and r.return_due_at is not null and r.return_due_at > now())
      );

    if v_duplicate_count > 0 then
      raise exception 'Tu as déjà ce livre en cours (réservé ou emprunté) — impossible de le réserver une deuxième fois avant de l''avoir rendu.';
    end if;

    select category into v_category from public.books where id = new.book_id;
    select count(*) into v_active_count
    from public.reservations r
    join public.books b on b.id = r.book_id
    where r.user_id = new.user_id
      and (
        r.status in ('preparation', 'pret')
        or (r.status = 'recupere' and r.return_due_at is not null and r.return_due_at > now())
      )
      and coalesce(b.category = 'Jeunesse', false) = coalesce(v_category = 'Jeunesse', false);
  else
    select category into v_category from public.free_books where id = new.free_book_id;
    select count(*) into v_active_count
    from public.free_book_loans l
    join public.free_books fb on fb.id = l.free_book_id
    where l.user_id = new.user_id and l.status in ('preparation', 'pret')
      and coalesce(fb.category = 'Jeunesse', false) = coalesce(v_category = 'Jeunesse', false);
  end if;

  v_is_jeunesse := (v_category = 'Jeunesse');

  if v_active_count >= 3 then
    if v_is_jeunesse then
      raise exception 'Limite atteinte : 3 livres jeunesse maximum en cours à la fois.';
    elsif tg_table_name = 'reservations' then
      raise exception 'Limite atteinte : 3 livres maximum en cours à la fois (hors jeunesse). Rapportez-en un pour en réserver un nouveau, ou prenez un livre hors condition avec « Prendre ce livre ».';
    else
      raise exception 'Limite atteinte : 3 livres hors condition maximum en cours à la fois (hors jeunesse). Rapportez-en un pour en prendre un nouveau.';
    end if;
  end if;

  return new;
end;
$$;
