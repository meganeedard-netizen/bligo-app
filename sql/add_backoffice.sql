-- BliGO — Back-office agent : rôles et permissions
-- À exécuter dans Supabase après sql/schema.sql (et add_bestsellers.sql si utilisé) :
-- SQL Editor > New query > coller > Run

-- 1. Rôle sur les profils : 'usager' (par défaut) ou 'agent' (personnel de la médiathèque)
alter table public.profiles
  add column if not exists role text not null default 'usager' check (role in ('usager', 'agent'));

-- Fonction utilitaire pour vérifier le rôle de l'utilisateur connecté sans provoquer
-- de récursion RLS (une policy sur profiles ne peut pas interroger profiles directement).
create or replace function public.is_agent()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'agent'
  );
$$;

-- 2. Un agent voit tous les profils (nécessaire pour afficher les usagers dans les réservations)
create policy "Un agent voit tous les profils"
  on public.profiles for select
  using (public.is_agent());

-- 3. Un agent gère le catalogue (catalogage : ajout, modification, suppression)
create policy "Un agent ajoute des livres"
  on public.books for insert
  with check (public.is_agent());

create policy "Un agent modifie les livres"
  on public.books for update
  using (public.is_agent());

create policy "Un agent supprime des livres"
  on public.books for delete
  using (public.is_agent());

-- 4. Un agent voit et met à jour toutes les réservations (gestion des réservations)
create policy "Un agent voit toutes les réservations"
  on public.reservations for select
  using (public.is_agent());

create policy "Un agent met à jour toutes les réservations"
  on public.reservations for update
  using (public.is_agent());

-- 5. Pour donner les droits agent à un compte existant (à faire une fois, manuellement) :
-- Dans Table Editor > profiles, trouve la ligne de la personne concernée et passe
-- sa colonne "role" à 'agent' — ou via SQL Editor :
-- update public.profiles set role = 'agent' where subscriber_number = 'VF-2026-00001';
