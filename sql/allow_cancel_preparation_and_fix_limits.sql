-- 1. Un usager peut retirer un livre de sa sélection tant qu'il est encore
-- "en préparation" (avant que la médiathèque ne commence à le préparer),
-- depuis Mes Réservations. Impossible une fois passé à "prêt" ou au-delà,
-- pour ne pas perturber un travail déjà engagé par la médiathèque.
create policy "Un usager annule sa réservation tant qu'elle est en préparation"
  on public.reservations for delete
  using (auth.uid() = user_id and status = 'preparation');

-- 2. Corrige la limite de 3 livres (hors jeunesse) + 3 livres jeunesse : elle
-- ne comptait jusqu'ici que les réservations "en préparation" ou "prêtes",
-- pas les livres déjà empruntés ("récupéré") — un usager pouvait donc réserver
-- 3 nouveaux livres tout en ayant déjà 3 livres chez lui, soit 6 en même
-- temps. On compte maintenant aussi les emprunts en cours (pas encore à leur
-- échéance de 3 semaines).
create or replace function public.enforce_reservation_limits()
returns trigger
language plpgsql
security definer
as $$
declare
  v_category text;
  v_is_jeunesse boolean;
  v_active_count integer;
begin
  if tg_table_name = 'reservations' then
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
