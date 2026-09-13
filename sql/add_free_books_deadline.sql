-- Les livres hors condition (Bibliothèque Libre) ont eux aussi 48h pour être
-- récupérés une fois pris, comme les réservations du catalogue officiel.
-- Il manquait une date de prise pour calculer ce délai (created_at est la
-- date d'ajout du livre, pas celle de la prise).

alter table public.free_books add column if not exists borrowed_at timestamptz;

-- Pour les livres déjà pris avant cette migration, on prend created_at à
-- défaut de mieux (mieux vaut une estimation que pas de délai du tout).
update public.free_books
set borrowed_at = created_at
where borrowed_by is not null and borrowed_at is null;

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
  set available = false, borrowed_by = auth.uid(), borrowed_at = now()
  where id = p_book_id and available = true;
  get diagnostics affected = row_count;

  if affected > 0 then
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
