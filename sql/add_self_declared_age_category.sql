-- BliGO — Auto-déclaration mineur/majeur à l'inscription (16/09/2026)
--
-- Décision du 16/09/2026 (voir [[project_bligo]]) : pas de date de naissance
-- stockée (RGPD). L'agent reste la seule source fiable (justificatif vérifié
-- en personne à la validation de la préinscription, voir set_tariff_category()
-- dans add_agent_roles_tariffs_and_age.sql). Mais entre l'inscription et cette
-- validation, le compte peut déjà réserver des livres (compte "flash") sans
-- aucune restriction d'âge tant que tariff_category est vide.
--
-- Cette migration ajoute une auto-déclaration à l'inscription (index.html,
-- case "Mineur·e / Majeur·e") : un premier réglage non vérifié, seulement pour
-- adapter le catalogue affiché dès le premier jour. L'agent corrige ensuite
-- si besoin lors de la validation — cette étape reste la seule qui compte
-- vraiment.
--
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

create or replace function public.handle_new_user()
returns trigger as $$
declare
  v_account_type text := case when new.raw_user_meta_data->>'account_type' = 'officiel' then 'officiel' else 'libre' end;
  v_commune_id bigint := nullif(new.raw_user_meta_data->>'commune_id', '')::bigint;
  v_self_declared text := nullif(new.raw_user_meta_data->>'self_declared_category', '');
begin
  insert into public.profiles (id, full_name, subscriber_number, account_type, commune_id, registration_status, tariff_category)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', 'Nouvel usager'),
    'VF-' || to_char(now(), 'YYYY') || '-' || lpad(floor(random() * 99999)::text, 5, '0'),
    v_account_type,
    case when v_account_type = 'officiel' then v_commune_id else null end,
    case when v_account_type = 'officiel' then 'pre_inscrit' else 'valide' end,
    case when v_self_declared in ('mineur', 'majeur') then v_self_declared else null end
  );
  return new;
end;
$$ language plpgsql security definer;
