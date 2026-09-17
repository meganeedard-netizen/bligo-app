-- Horaires d'ouverture de la médiathèque (17/09/2026)
-- ============================================================
-- Texte libre par jour (pas de créneaux horaires structurés) : certaines
-- médiathèques ferment le midi, d'autres pas, d'autres ont des horaires
-- différents en période scolaire — plus simple de laisser l'agent écrire
-- "9h - 12h / 14h - 18h" ou "Fermé" que d'imposer un format rigide.

alter table public.communes add column if not exists opening_hours jsonb;
comment on column public.communes.opening_hours is 'Horaires d''ouverture, texte libre par jour : {"lundi": "...", "mardi": "...", ..., "dimanche": "..."}. Modifiable par la direction depuis Comptes & tarifs.';

create or replace function public.update_commune_opening_hours(
  p_commune_id bigint, p_opening_hours jsonb
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
    set opening_hours = p_opening_hours
    where id = p_commune_id;
end;
$$;
