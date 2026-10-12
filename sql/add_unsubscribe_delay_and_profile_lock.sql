-- 12/10/2026
-- 1. Délai de désinscription des événements, réglé par l'agent (48 h par défaut)
-- 2. Sécurité : un usager ne peut modifier lui-même que ses préférences
--    (nom, catégories préférées, rythme de lecture, notifications). Le rôle,
--    la médiathèque, le statut d'inscription, la catégorie d'abonnement, les
--    points, etc. ne peuvent être changés que par un agent ou par les
--    fonctions de BliGO. Avant ce correctif, un usager pouvait techniquement
--    se donner le rôle d'agent.

-- 1. Délai de désinscription
alter table public.events
  add column if not exists unsubscribe_hours integer not null default 48;

-- 2. Verrou sur les colonnes sensibles des profils
create or replace function public.protect_profile_columns()
returns trigger
language plpgsql
-- Pas « security definer » : current_user doit rester celui de l'appelant
-- (« authenticated » pour l'appli, propriétaire pour les fonctions BliGO).
set search_path = public
as $$
declare
  -- Colonnes qu'un usager a le droit de modifier lui-même depuis l'appli.
  allowed text[] := array[
    'full_name', 'preferred_categories', 'onboarding_completed',
    'reading_pace', 'reading_goal', 'notifications_enabled'
  ];
begin
  -- Les fonctions BliGO (security definer) et les mises à jour faites par
  -- d'autres déclencheurs (points, badges...) ne sont pas concernées.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if pg_trigger_depth() > 1 then
    return new;
  end if;
  -- Agents et super admin : pas de restriction (les règles d'accès s'appliquent).
  if public.is_agent() then
    return new;
  end if;
  if (to_jsonb(new) - allowed) is distinct from (to_jsonb(old) - allowed) then
    raise exception 'Modification non autorisée : seuls ton nom et tes préférences peuvent être modifiés depuis l''appli.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_profile_columns on public.profiles;
create trigger trg_protect_profile_columns
  before update on public.profiles
  for each row execute function public.protect_profile_columns();
