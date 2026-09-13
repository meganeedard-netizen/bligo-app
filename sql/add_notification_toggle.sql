-- Active/désactive réellement les alertes de disponibilité : sans ce réglage
-- (désactivé par défaut, à activer explicitement par l'usager), le trigger
-- de notification "livre de nouveau disponible" ne s'exécute plus.

alter table public.profiles add column if not exists notifications_enabled boolean not null default false;

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
    join public.profiles p on p.id = w.user_id
    where w.book_id = new.id and p.notifications_enabled = true;
  end if;
  return new;
end;
$$;
