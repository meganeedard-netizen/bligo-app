-- Limite le nombre de livres en cours par usager : 3 maximum hors jeunesse,
-- + 3 maximum en catégorie Jeunesse. Le catalogue officiel et les livres hors
-- condition ont chacun leur propre quota (indépendants l'un de l'autre) :
-- atteindre la limite du catalogue n'empêche pas de prendre un livre hors
-- condition, et inversement. Appliquée en base (trigger) pour ne pas
-- dépendre du chemin d'insertion côté client.

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
    where r.user_id = new.user_id and r.status in ('preparation', 'pret')
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

drop trigger if exists trg_enforce_reservation_limits on public.reservations;
create trigger trg_enforce_reservation_limits
  before insert on public.reservations
  for each row execute procedure public.enforce_reservation_limits();

drop trigger if exists trg_enforce_free_loan_limits on public.free_book_loans;
create trigger trg_enforce_free_loan_limits
  before insert on public.free_book_loans
  for each row execute procedure public.enforce_reservation_limits();
