-- 16/10/2026
-- Retirer un visiteur compté par erreur (bouton « −1 » du back-office).
-- On enlève une personne à la dernière entrée du jour de la médiathèque :
-- une entrée de groupe perd 1 personne, une entrée seule est supprimée.
-- Le retrait est noté dans le journal d'activité. Les statistiques annuelles
-- (sum(count)) restent justes sans autre changement.

create or replace function public.remove_visitor_entry()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commune bigint;
  v_entry public.visitor_entries%rowtype;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  v_commune := public.agent_commune_id();
  if v_commune is null then
    raise exception 'Aucune médiathèque associée à ce compte agent';
  end if;

  select * into v_entry
    from public.visitor_entries
   where commune_id = v_commune
     and occurred_at::date = current_date
   order by occurred_at desc, id desc
   limit 1;

  if not found then
    raise exception 'Aucun visiteur à retirer aujourd''hui';
  end if;

  if v_entry.count > 1 then
    update public.visitor_entries set count = count - 1 where id = v_entry.id;
  else
    delete from public.visitor_entries where id = v_entry.id;
  end if;

  perform public.log_activity('visitor_entry_removed', v_commune, 'visitor_entry', null,
    jsonb_build_object('entry_id', v_entry.id));

  return public.visitor_count_today();
end;
$$;

revoke all on function public.remove_visitor_entry() from public, anon;
grant execute on function public.remove_visitor_entry() to authenticated;
