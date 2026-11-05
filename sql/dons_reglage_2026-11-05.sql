-- Dons de livres en option par médiathèque (05/11/2026, demande de Mégane).
-- communes.donations_enabled, réglé par la direction dans le logiciel
-- (Réglages > Tarifs et conditions).
-- Médiathèques déjà existantes : dons laissés ACTIFS, rien ne change pour elles.
-- Nouvelles médiathèques : dons DÉSACTIVÉS tant que la direction ne les active pas.
-- Ré-exécutable sans danger : relancé, il ne touche pas aux choix déjà faits.
-- À exécuter dans Supabase (SQL Editor > New query > coller > Run).

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'communes' and column_name = 'donations_enabled'
  ) then
    alter table public.communes add column donations_enabled boolean not null default false;
    update public.communes set donations_enabled = true;
  end if;
end $$;

comment on column public.communes.donations_enabled is
  'La médiathèque accepte les dons de livres (bouton au catalogage, défi et badge dans l''appli).';

-- Le réglage est aussi contrôlé côté serveur, pas seulement masqué à l'écran.
create or replace function public.check_donations_enabled()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commune_id bigint;
begin
  select coalesce(
    public.agent_commune_id(),
    (select p.commune_id from public.profiles p where p.id = new.donor_id)
  ) into v_commune_id;

  if exists (select 1 from public.communes c where c.id = v_commune_id and not c.donations_enabled) then
    raise exception 'Cette médiathèque n''accepte pas les dons de livres pour le moment. La direction peut les activer dans Réglages.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_check_donations_enabled on public.donations;
create trigger trg_check_donations_enabled
  before insert on public.donations
  for each row execute function public.check_donations_enabled();

create or replace function public.update_commune_donations_setting(p_commune_id bigint, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;
  update public.communes set donations_enabled = coalesce(p_enabled, false) where id = p_commune_id;
end;
$$;

grant execute on function public.update_commune_donations_setting(bigint, boolean) to authenticated;
