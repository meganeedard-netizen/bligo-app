-- Réseau de démo : comptes (agents + usager), dépôts BDP, prêts de l'année, demande en attente
do $$
declare
  v_bdp bigint := 8; v_libs bigint[] := array[9, 10, 11];
  v_agents uuid[] := array['59ef841c-627d-4f27-8a61-f6be71eaa8d4','1e610a74-6c23-413f-8b23-107ed4ff0ba6','a92f533b-a587-44ca-a15c-63b97ab590d8']::uuid[];
  v_usager uuid := '89cbdcab-6e64-4b9e-9f12-32cf8ddbd0d3';
  c record; v_k int := 0; v_lib bigint; v_start timestamptz; v_req_copy bigint; v_req_book bigint;
begin
  if not exists (select 1 from public.communities co join public.communes cm on cm.community_id = co.id
                 where cm.id = v_bdp and co.is_demo and cm.is_bdp) then
    raise exception 'Commune 8 n''est pas la BDP de démo';
  end if;

  update public.profiles set role = 'agent', agent_level = 'direction', registration_status = 'valide',
         validated_at = now(), commune_confirmed = true, onboarding_completed = true, email_verifie = true
   where id in ('b8ecc614-4808-425c-bed3-ed6bd812438c', '59ef841c-627d-4f27-8a61-f6be71eaa8d4',
                '1e610a74-6c23-413f-8b23-107ed4ff0ba6', 'a92f533b-a587-44ca-a15c-63b97ab590d8');
  update public.profiles set registration_status = 'valide', validated_at = now(), commune_confirmed = true,
         onboarding_completed = true, email_verifie = true, tariff_category = 'majeur',
         membership_expires_at = now() + interval '10 months'
   where id = v_usager;

  -- 24 exemplaires de la BDP en dépôt (8 par bibliothèque), depuis 2 semaines à 8 mois
  for c in select id, book_id from public.book_copies where owner_commune_id = v_bdp order by id limit 24 loop
    v_k := v_k + 1;
    v_lib := v_libs[1 + (v_k - 1) % 3];
    v_start := now() - ((14 + (v_k * 11) % 230) || ' days')::interval;
    insert into public.depots (copy_id, bdp_commune_id, library_commune_id, started_at)
    values (c.id, v_bdp, v_lib, v_start);
    insert into public.transfers (copy_id, from_commune_id, to_commune_id, status, requested_by, sent_by, received_by,
                                  requested_at, sent_at, received_at, kind, notes)
    values (c.id, v_bdp, v_lib, 'received', 'b8ecc614-4808-425c-bed3-ed6bd812438c', 'b8ecc614-4808-425c-bed3-ed6bd812438c',
            v_agents[1 + (v_k - 1) % 3], v_start - interval '3 days', v_start - interval '1 day', v_start, 'depot', 'Navette mensuelle');
    update public.book_copies set current_commune_id = v_lib where id = c.id;
    if v_lib = 9 and v_start < now() - interval '90 days' and v_req_copy is null then
      v_req_copy := c.id; v_req_book := c.book_id;
    end if;
  end loop;

  -- Prêts de l'année (rendus) : 3 à 6 par exemplaire en bibliothèque, répartis sur 10 mois
  insert into public.loans (copy_id, user_id, borrowed_at_commune_id, returned_at_commune_id, borrowed_at, due_at, returned_at,
                            borrowed_by_agent, returned_by_agent, reshelved)
  select bc.id, v_usager, bc.current_commune_id, bc.current_commune_id,
         now() - ((g * 45 + (bc.id % 30)) || ' days')::interval,
         now() - ((g * 45 + (bc.id % 30) - 21) || ' days')::interval,
         now() - ((g * 45 + (bc.id % 30) - 18) || ' days')::interval,
         v_agents[array_position(v_libs, bc.current_commune_id)], v_agents[array_position(v_libs, bc.current_commune_id)], true
  from public.book_copies bc
  cross join generate_series(1, 6) g
  where bc.current_commune_id = any (v_libs) and g <= 3 + (bc.id % 4)
    and g * 45 + (bc.id % 30) < 320;

  -- 3 prêts en cours pour l'usager de démo à Monte-Alto (dont 1 document de la BDP en dépôt)
  for c in (select bc.id from public.book_copies bc where bc.owner_commune_id = 9 order by bc.id limit 2)
           union all (select bc.id from public.book_copies bc join public.depots d on d.copy_id = bc.id and d.ended_at is null
                      where d.library_commune_id = 9 and bc.id is distinct from v_req_copy order by bc.id limit 1) loop
    insert into public.loans (copy_id, user_id, borrowed_at_commune_id, borrowed_at, due_at, borrowed_by_agent)
    values (c.id, v_usager, 9, now() - interval '6 days', now() + interval '15 days', v_agents[1]);
    update public.book_copies set status = 'borrowed' where id = c.id;
  end loop;

  -- Pietra-Bianca demande un document de la BDP en dépôt à Monte-Alto depuis plus de 3 mois
  if v_req_book is not null then
    insert into public.depot_requests (book_id, bdp_commune_id, library_commune_id, requested_by, status, created_at)
    values (v_req_book, v_bdp, 11, v_agents[3], 'open', now() - interval '2 days');
  end if;
end $$;

select (select count(*) from public.depots where bdp_commune_id = 8 and ended_at is null) depots_ouverts,
       (select count(*) from public.loans l join public.book_copies bc on bc.id = l.copy_id join public.communes cm on cm.id = bc.owner_commune_id join public.communities co on co.id = cm.community_id where co.is_demo) prets,
       (select count(*) from public.depot_requests where bdp_commune_id = 8 and status = 'open') demandes,
       (select string_agg(full_name || ':' || role || ':' || commune_id, ' | ') from public.profiles where full_name like '%démo%' or full_name = 'Lecteur de démo') comptes;
