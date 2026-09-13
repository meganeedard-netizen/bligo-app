-- Deux types de compte usager :
--   'officiel' — rattaché à une commune partenaire, accède au Click & Collect
--                du catalogue officiel de sa commune. Nécessite la validation
--                d'un agent (pièce d'identité + justificatif de domicile).
--   'libre'    — pas rattaché à une commune (pas encore de mairie partenaire
--                chez lui). Accède librement à la Bibliothèque Libre (dons,
--                hors condition), sans validation nécessaire. Peut demander
--                son rattachement à une commune dès qu'il en a une, ce qui le
--                fait basculer en compte 'officiel' (en attente de validation).

-- 1. Renomme l'ancienne valeur 'flash' (posée en fondation, jamais utilisée
-- côté appli) en 'libre', qui devient le type par défaut à l'inscription.
alter table public.profiles drop constraint if exists profiles_account_type_check;
update public.profiles set account_type = 'libre' where account_type = 'flash';
alter table public.profiles add constraint profiles_account_type_check check (account_type in ('officiel', 'libre'));
alter table public.profiles alter column account_type set default 'libre';

-- 2. Commune de rattachement (uniquement pour les comptes 'officiel')
alter table public.profiles add column if not exists commune_id bigint references public.communes(id);

-- 3. À l'inscription : le type de compte et la commune (si 'officiel') sont
-- fournis par le formulaire d'inscription via les métadonnées utilisateur.
-- Un compte 'libre' n'ayant aucune condition de résidence à prouver, il est
-- validé automatiquement ; un compte 'officiel' part en pré-inscription et
-- suit le circuit de validation déjà en place (voir add_preregistration.sql).
create or replace function public.handle_new_user()
returns trigger as $$
declare
  v_account_type text := case when new.raw_user_meta_data->>'account_type' = 'officiel' then 'officiel' else 'libre' end;
  v_commune_id bigint := nullif(new.raw_user_meta_data->>'commune_id', '')::bigint;
begin
  insert into public.profiles (id, full_name, subscriber_number, account_type, commune_id, registration_status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', 'Nouvel usager'),
    'VF-' || to_char(now(), 'YYYY') || '-' || lpad(floor(random() * 99999)::text, 5, '0'),
    v_account_type,
    case when v_account_type = 'officiel' then v_commune_id else null end,
    case when v_account_type = 'officiel' then 'pre_inscrit' else 'valide' end
  );
  return new;
end;
$$ language plpgsql security definer;

-- 4. Un compte 'libre' peut demander son rattachement à une commune dès qu'il
-- en a une : il repasse alors en pré-inscription (une nouvelle résidence à
-- prouver auprès d'un agent, comme n'importe quelle inscription officielle).
create or replace function public.request_commune_attachment(p_commune_id bigint)
returns void
language plpgsql
security definer
as $$
begin
  update public.profiles
  set account_type = 'officiel',
      commune_id = p_commune_id,
      registration_status = 'pre_inscrit',
      validated_at = null,
      validated_by = null
  where id = auth.uid();
end;
$$;

grant execute on function public.request_commune_attachment(bigint) to authenticated;
