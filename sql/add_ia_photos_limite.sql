-- BliGO - limite mensuelle de lectures IA des photos de livre (02/11/2026)
--
-- Chaque photo lue par l'IA (résumé au dos ou contrôle de couverture) coûte
-- environ 1 centime. Chaque médiathèque a un plafond par mois (300 par
-- défaut) ; au-delà, le logiciel garde l'ancienne lecture et prévient l'agent.
-- Le compteur repart le 1er du mois. Le super-admin n'est pas limité.

alter table public.communes add column if not exists ia_photos_limite_mois integer not null default 300;

create table if not exists public.ia_photos_usage (
  id bigint generated always as identity primary key,
  commune_id bigint references public.communes(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  mode text not null,
  model text not null,
  created_at timestamptz not null default now()
);

create index if not exists ia_photos_usage_commune_mois on public.ia_photos_usage (commune_id, created_at);

-- Écrite seulement par l'Edge Function lire-photo-livre (clé de service) ;
-- lecture réservée au super-admin pour suivre la consommation.
alter table public.ia_photos_usage enable row level security;

drop policy if exists "Le super-admin voit la consommation IA" on public.ia_photos_usage;
create policy "Le super-admin voit la consommation IA"
  on public.ia_photos_usage for select
  using (public.is_super_admin());

-- Pour régler une médiathèque à part (gros catalogage par exemple) :
--   update public.communes set ia_photos_limite_mois = 600 where name = 'Val-Fleuri';
