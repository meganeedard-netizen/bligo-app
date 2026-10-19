-- Adresse de la médiathèque (19/10/2026)
-- ============================================================
-- Affichée aux usagers dans Mes réservations, sous la médiathèque : toucher
-- l'adresse propose de lancer la navigation (Plans, Google Maps ou Waze).
-- Modifiable par la direction depuis Réglages › Adresse et horaires.

alter table public.communes add column if not exists address text not null default '';
comment on column public.communes.address is 'Adresse postale complète de la médiathèque (rue, code postal, ville), utilisée pour la navigation GPS des usagers.';

create or replace function public.update_commune_address(
  p_commune_id bigint, p_address text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;

  update public.communes
    set address = trim(coalesce(p_address, ''))
    where id = p_commune_id;
end;
$$;
