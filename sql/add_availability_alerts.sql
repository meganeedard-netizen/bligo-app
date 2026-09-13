-- "Recevoir une alerte" sur un livre indisponible du catalogue officiel :
-- réutilise la liste d'envie déjà en place (un livre indisponible ajouté à la
-- wishlist = une alerte). Dès qu'un agent repasse le livre en disponible,
-- tous les usagers qui l'ont dans leur liste d'envie reçoivent une notification.

create or replace function public.notify_wishlist_on_availability()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.available = true and old.available = false then
    insert into public.notifications (user_id, message)
    select w.user_id, '🔔 Bonne nouvelle ! « ' || new.title || ' » est de nouveau disponible à la médiathèque.'
    from public.wishlist w
    where w.book_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_wishlist_on_availability on public.books;
create trigger trg_notify_wishlist_on_availability
  after update on public.books
  for each row execute procedure public.notify_wishlist_on_availability();
