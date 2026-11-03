-- Suppression d'un compte par le super-admin, depuis l'espace admin BliGO
-- (03/11/2026, demandé par Mégane : comptes de test, usager qui le demande
-- par e-mail). Même nettoyage que delete_my_account (sql/add_suppression_compte_immediate.sql).
--
-- admin_find_account(email) : retrouve le compte avant de le supprimer.
-- admin_delete_account(id) : refuse son propre compte et les autres
-- super-admins ; mêmes conditions que pour l'usager (aucun emprunt en cours,
-- aucune dette ouverte).

create or replace function public.admin_find_account(p_email text)
returns table (id uuid, email text, full_name text, role text, created_at timestamptz, providers jsonb, commune_name text)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'super_admin') then
    raise exception 'Réservé au super-admin';
  end if;
  return query
    select u.id, u.email::text, pr.full_name, pr.role::text, u.created_at, u.raw_app_meta_data->'providers', c.name
    from auth.users u
    left join public.profiles pr on pr.id = u.id
    left join public.communes c on c.id = pr.commune_id
    where lower(u.email) = lower(trim(p_email));
end;
$$;

create or replace function public.admin_delete_account(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  fk record;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'super_admin') then
    return jsonb_build_object('ok', false, 'message', 'Réservé au super-admin.');
  end if;
  if p_user_id = auth.uid() then
    return jsonb_build_object('ok', false, 'message', 'Tu ne peux pas supprimer ton propre compte ici.');
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    return jsonb_build_object('ok', false, 'message', 'Compte introuvable.');
  end if;
  if exists (select 1 from public.profiles where id = p_user_id and role = 'super_admin') then
    return jsonb_build_object('ok', false, 'message', 'Un compte super-admin ne peut pas être supprimé ici.');
  end if;
  if exists (select 1 from public.loans where user_id = p_user_id and returned_at is null) then
    return jsonb_build_object('ok', false, 'message', 'Ce compte a encore des documents empruntés : ils doivent être rendus avant la suppression.');
  end if;
  if exists (select 1 from public.document_debts where user_id = p_user_id and status = 'open') then
    return jsonb_build_object('ok', false, 'message', 'Un document perdu ou abîmé reste à régler pour ce compte.');
  end if;

  delete from public.reservations where user_id = p_user_id and status in ('panier', 'preparation', 'pret');

  for fk in
    select c.conrelid::regclass as tbl, a.attname as col, a.attnotnull as notnull
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f'
      and c.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass)
      and c.confdeltype <> 'c'
      and array_length(c.conkey, 1) = 1
      and c.conrelid::regclass::text not like 'auth.%'
  loop
    if fk.notnull then
      execute format('delete from %s where %I = $1', fk.tbl, fk.col) using p_user_id;
    else
      execute format('update %s set %I = null where %I = $1', fk.tbl, fk.col, fk.col) using p_user_id;
    end if;
  end loop;

  delete from public.profiles where id = p_user_id;
  delete from auth.users where id = p_user_id;

  return jsonb_build_object('ok', true, 'message', 'Compte supprimé.');
end;
$$;

revoke all on function public.admin_find_account(text) from public, anon;
revoke all on function public.admin_delete_account(uuid) from public, anon;
grant execute on function public.admin_find_account(text) to authenticated;
grant execute on function public.admin_delete_account(uuid) to authenticated;
