-- BliGO, droits sur les notices et les paniers (23/11/2026, choix de Mégane) :
-- l'agent qui a ajouté + la direction modifient, les autres lisent ; la
-- direction réattribue. Réglage par médiathèque, 'ouvert' par défaut.
alter table public.communes add column if not exists catalog_rights text not null default 'ouvert';
do $$ begin
  alter table public.communes add constraint communes_catalog_rights_check check (catalog_rights in ('ouvert', 'auteur'));
exception when duplicate_object then null; end $$;

create or replace function public.can_edit_book(p_book_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_agent() and (
    public.is_direction()
    or coalesce((select c.catalog_rights from public.books b join public.communes c on c.id = b.commune_id where b.id = p_book_id), 'ouvert') = 'ouvert'
    or exists (select 1 from public.book_catalogers k where k.book_id = p_book_id and k.agent_id = auth.uid()));
$$;
revoke all on function public.can_edit_book(bigint) from public, anon;
grant execute on function public.can_edit_book(bigint) to authenticated;

-- Seules les données de la notice sont protégées : équipement, disponibilité,
-- rangement et circulation restent possibles pour tous les agents.
create or replace function public.trg_protect_book_notice() returns trigger
language plpgsql security definer set search_path = public as $$
declare k text[] := array['available','equipped','shelf_location','is_featured','archived','loan_duration_days_override','is_new_release','is_staff_pick','on_site_only','cover_color'];
begin
  if auth.uid() is not null and public.is_agent() and (to_jsonb(new) - k) is distinct from (to_jsonb(old) - k)
     and not public.can_edit_book(old.id) then
    raise exception 'Cette notice est en lecture seule : seuls l''agent qui l''a ajoutée et la direction peuvent la modifier.';
  end if;
  return new;
end $$;
drop trigger if exists trg_books_protect_notice on public.books;
create trigger trg_books_protect_notice before update on public.books for each row execute function public.trg_protect_book_notice();

create or replace function public.trg_protect_draft() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and old.agent_id <> auth.uid() and not public.is_direction()
     and (select catalog_rights from public.communes where id = old.commune_id) = 'auteur' then
    raise exception 'Ce panier appartient à un autre agent. La direction peut te l''attribuer.';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists trg_catalog_drafts_protect on public.catalog_drafts;
create trigger trg_catalog_drafts_protect before update or delete on public.catalog_drafts for each row execute function public.trg_protect_draft();

create or replace function public.commune_agents() returns table (id uuid, full_name text)
language sql stable security definer set search_path = public as $$
  select p.id, p.full_name from public.profiles p
   where public.is_agent() and p.role in ('agent', 'super_admin') and p.commune_id = public.agent_commune_id() order by p.full_name;
$$;
create or replace function public.reassign_book(p_book_id bigint, p_to uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_direction() or not exists (select 1 from public.books where id = p_book_id and (commune_id = public.agent_commune_id() or public.is_super_admin())) then raise exception 'Réservé à la direction de cette médiathèque.'; end if;
  if not exists (select 1 from public.books b join public.profiles p on p.commune_id = b.commune_id where b.id = p_book_id and p.id = p_to and p.role in ('agent', 'super_admin')) then raise exception 'Cet agent n''est pas de la médiathèque.'; end if;
  insert into public.book_catalogers (book_id, agent_id) values (p_book_id, p_to)
  on conflict (book_id) do update set agent_id = excluded.agent_id;
end $$;
create or replace function public.reassign_catalog_lot(p_from uuid, p_lot text, p_to uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.is_direction() then raise exception 'Réservé à la direction.'; end if;
  if not exists (select 1 from public.profiles where id = p_to and role in ('agent', 'super_admin') and commune_id = public.agent_commune_id()) then raise exception 'Cet agent n''est pas de la médiathèque.'; end if;
  update public.catalog_drafts d set agent_id = p_to, updated_at = now()
   where d.agent_id = p_from and d.lot is not distinct from p_lot and d.commune_id = public.agent_commune_id();
  get diagnostics n = row_count; return n;
end $$;
create or replace function public.set_catalog_rights(p_value text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_direction() then raise exception 'Réservé à la direction.'; end if;
  update public.communes set catalog_rights = p_value where id = public.agent_commune_id();
end $$;
create or replace function public.take_over_catalog_lot(p_agent uuid, p_lot text) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not (public.is_agent() or public.is_super_admin()) then raise exception 'Accès réservé aux agents'; end if;
  delete from public.catalog_drafts d where d.agent_id = p_agent and d.lot is not distinct from p_lot and d.commune_id = public.agent_commune_id()
    and p_agent <> auth.uid()
    and exists (select 1 from public.catalog_drafts m where m.agent_id = auth.uid() and m.local_id = d.local_id);
  update public.catalog_drafts set agent_id = auth.uid(), updated_at = now()
   where agent_id = p_agent and lot is not distinct from p_lot and commune_id = public.agent_commune_id();
  get diagnostics n = row_count; return n;
end $$;
revoke all on function public.commune_agents(), public.reassign_book(bigint, uuid), public.reassign_catalog_lot(uuid, text, uuid), public.set_catalog_rights(text) from public, anon;
grant execute on function public.commune_agents(), public.reassign_book(bigint, uuid), public.reassign_catalog_lot(uuid, text, uuid), public.set_catalog_rights(text) to authenticated;

-- Supprimer une notice suit la même règle que la modifier (24/11/2026).
create or replace function public.trg_protect_book_delete() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and public.is_agent() and not public.can_edit_book(old.id) then
    raise exception 'Cette notice est en lecture seule : seuls l''agent qui l''a ajoutée et la direction peuvent la supprimer.';
  end if;
  return old;
end $$;
drop trigger if exists trg_books_protect_delete on public.books;
create trigger trg_books_protect_delete before delete on public.books for each row execute function public.trg_protect_book_delete();
