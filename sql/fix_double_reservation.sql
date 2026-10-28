-- Correctif (28/10/2026) : un livre déjà commandé par un usager ne doit plus
-- pouvoir être commandé par un autre (cas « Pluie et vent sur Télumée Miracle »,
-- commandé par Linda Marie puis par Mégane).
--
-- Cause : une commande (preparation / pret) ne change pas le statut de
-- l'exemplaire, qui reste « available ». books.available restait donc vrai et
-- l'insertion dans reservations n'était jamais refusée.
--
-- 1. books.available = au moins un exemplaire libre (free_copies_count), en
--    tenant compte des commandes en cours. Le catalogue affiche alors le livre
--    indisponible avec « Ajouter à la file d'attente ».
-- 2. Refus en base de toute nouvelle commande si aucun exemplaire n'est libre
--    (sauf la mise de côté automatique de la file d'attente).

-- ------------------------------------------------------------
-- 1. Disponibilité calculée avec les commandes en cours
-- ------------------------------------------------------------
create or replace function public.refresh_book_available(p_book_id bigint)
returns void
language sql
security definer
set search_path = public
as $$
  update public.books
     set available = public.free_copies_count(p_book_id) > 0
   where id = p_book_id
     and archived is not true
     and available is distinct from (public.free_copies_count(p_book_id) > 0);
$$;

-- Exemplaires : même déclencheur qu'avant, nouveau calcul.
create or replace function public.sync_book_availability()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.refresh_book_available(coalesce(new.book_id, old.book_id));
  return coalesce(new, old);
end;
$$;

-- Commandes : une commande passée, annulée, expirée ou récupérée recalcule
-- la disponibilité du livre.
create or replace function public.sync_book_availability_from_reservation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.refresh_book_available(coalesce(new.book_id, old.book_id));
  if tg_op = 'UPDATE' and new.book_id is distinct from old.book_id then
    perform public.refresh_book_available(old.book_id);
  end if;
  return null;
end;
$$;

drop trigger if exists trg_sync_book_availability_reservation on public.reservations;
create trigger trg_sync_book_availability_reservation
  after insert or update of status, book_id or delete on public.reservations
  for each row execute function public.sync_book_availability_from_reservation();

-- ------------------------------------------------------------
-- 2. Refus d'une commande sur un livre sans exemplaire libre
-- ------------------------------------------------------------
create or replace function public.check_reservation_book_free()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status not in ('preparation', 'pret') then
    return new;
  end if;
  -- Mise de côté pour le premier de la file d'attente : l'exemplaire est déjà
  -- réservé pour lui.
  if current_setting('bligo.hold_promotion', true) = 'on' then
    return new;
  end if;

  -- Verrou sur le livre : deux usagers qui commandent à la même seconde
  -- passent l'un après l'autre.
  perform 1 from public.books where id = new.book_id for update;

  if public.free_copies_count(new.book_id) <= 0 then
    raise exception 'Ce livre est déjà réservé par un autre usager.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_check_reservation_book_free on public.reservations;
create trigger trg_check_reservation_book_free
  before insert on public.reservations
  for each row execute function public.check_reservation_book_free();

-- ------------------------------------------------------------
-- 3. Rattrapage : recalcul de tous les livres
-- ------------------------------------------------------------
select public.refresh_book_available(id) from public.books where archived is not true;

-- ------------------------------------------------------------
-- 4. Contrôle (lecture) : livres commandés en même temps par plusieurs
--    usagers alors qu'il n'y a pas assez d'exemplaires. À régler à la main.
-- ------------------------------------------------------------
select b.title, u.email, r.id as reservation_id, r.status, r.created_at
  from public.reservations r
  join public.books b on b.id = r.book_id
  join auth.users u on u.id = r.user_id
 where r.status in ('preparation', 'pret')
   and (select count(*) from public.reservations r2
         where r2.book_id = r.book_id and r2.status in ('preparation', 'pret'))
       > (select count(*) from public.book_copies c
           where c.book_id = r.book_id and c.status in ('available', 'reserved'))
 order by b.title, r.created_at;
