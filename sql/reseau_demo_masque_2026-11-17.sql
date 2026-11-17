-- Réseau de démonstration : invisible pour les vrais usagers et agents (17/11/2026)
-- Un réseau (communities) marqué is_demo = true n'est visible que :
--   - par les comptes rattachés à une commune de CE réseau (agents et usagers de démo),
--   - par l'administratrice BliGO (super-admin).
-- Les visiteurs sans compte et tous les autres comptes ne voient ni ses communes,
-- ni ses livres, ni ses exemplaires. Valable aussi pour l'appli mobile déjà publiée.

alter table public.communities add column if not exists is_demo boolean not null default false;

-- Communes cachées pour la personne connectée (calculé une seule fois par requête)
create or replace function public.hidden_commune_ids()
returns bigint[]
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(array_agg(cm.id), '{}'::bigint[])
  from public.communes cm
  join public.communities co on co.id = cm.community_id
  where co.is_demo
    and not public.is_super_admin()
    and cm.community_id is distinct from (
      select c2.community_id
      from public.profiles p
      join public.communes c2 on c2.id = p.commune_id
      where p.id = auth.uid()
    );
$$;

grant execute on function public.hidden_commune_ids() to anon, authenticated;

drop policy if exists "Les communes sont publiques en lecture" on public.communes;
create policy "Les communes sont publiques en lecture" on public.communes
  for select using (not (id = any ((select public.hidden_commune_ids())::bigint[])));

drop policy if exists "Le catalogue est public en lecture" on public.books;
create policy "Le catalogue est public en lecture" on public.books
  for select using (commune_id is null or not (commune_id = any ((select public.hidden_commune_ids())::bigint[])));

drop policy if exists "Les exemplaires sont publics en lecture" on public.book_copies;
create policy "Les exemplaires sont publics en lecture" on public.book_copies
  for select using (not (owner_commune_id = any ((select public.hidden_commune_ids())::bigint[])));

-- Complément : un compte du réseau de démo ne voit QUE son réseau (pas Val-Fleuri ni les vrais clients)
create or replace function public.hidden_commune_ids()
returns bigint[]
language sql
stable
security definer
set search_path to 'public'
as $$
  with moi as (
    select c2.community_id, co2.is_demo
    from public.profiles p
    join public.communes c2 on c2.id = p.commune_id
    join public.communities co2 on co2.id = c2.community_id
    where p.id = auth.uid()
  )
  select coalesce(array_agg(cm.id), '{}'::bigint[])
  from public.communes cm
  join public.communities co on co.id = cm.community_id
  where not public.is_super_admin()
    and (
      -- vrais comptes et visiteurs : réseaux de démo cachés
      (co.is_demo and cm.community_id is distinct from (select community_id from moi))
      -- comptes de démo : tout ce qui n'est pas leur réseau est caché
      or (coalesce((select is_demo from moi), false) and cm.community_id is distinct from (select community_id from moi))
    );
$$;
