-- 12/10/2026
-- Accès au back-office : seule l'administratrice de BliGO (super_admin) peut
-- basculer un compte usager existant en compte agent d'une médiathèque, ou
-- lui retirer cet accès. Le bouton « Back-office » n'apparaît dans le profil
-- de l'appli qu'à partir de ce moment-là.

create or replace function public.promote_user_to_agent(p_email text, p_commune_id bigint, p_level text default 'agent')
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_name text;
  v_role text;
begin
  -- Uniquement le compte de Mégane (megane@bligo.fr), administratrice de BliGO.
  if not exists (
    select 1 from public.profiles p join auth.users u on u.id = p.id
    where p.id = auth.uid() and p.role = 'super_admin' and lower(u.email) = 'megane@bligo.fr'
  ) then
    raise exception 'Réservé à l''administratrice de BliGO';
  end if;
  if p_level not in ('agent', 'direction') then
    raise exception 'Niveau invalide : %', p_level;
  end if;
  if not exists (select 1 from public.communes where id = p_commune_id) then
    raise exception 'Médiathèque introuvable';
  end if;

  select u.id into v_user_id from auth.users u where lower(u.email) = lower(trim(p_email));
  if v_user_id is null then
    raise exception 'Aucun compte BliGO avec l''adresse %. La personne doit d''abord créer son compte dans l''appli.', trim(p_email);
  end if;

  select full_name, role into v_name, v_role from public.profiles where id = v_user_id;
  if v_role = 'super_admin' then
    raise exception 'Ce compte est celui de l''administratrice de BliGO';
  end if;

  update public.profiles
     set role = 'agent', agent_level = p_level, commune_id = p_commune_id
   where id = v_user_id;

  return coalesce(v_name, trim(p_email));
end;
$$;

create or replace function public.revoke_agent_access(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Uniquement le compte de Mégane (megane@bligo.fr), administratrice de BliGO.
  if not exists (
    select 1 from public.profiles p join auth.users u on u.id = p.id
    where p.id = auth.uid() and p.role = 'super_admin' and lower(u.email) = 'megane@bligo.fr'
  ) then
    raise exception 'Réservé à l''administratrice de BliGO';
  end if;
  update public.profiles set role = 'usager', agent_level = null
   where id = p_user_id and role = 'agent';
end;
$$;

revoke all on function public.promote_user_to_agent(text, bigint, text) from public, anon;
revoke all on function public.revoke_agent_access(uuid) from public, anon;
grant execute on function public.promote_user_to_agent(text, bigint, text) to authenticated;
grant execute on function public.revoke_agent_access(uuid) to authenticated;
