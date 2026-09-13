-- BliGO — Rôle super-admin + commune des usagers
-- À exécuter dans Supabase (SQL Editor > New query > coller > Run), après add_backoffice.sql

-- 1. Élargit le rôle : 'usager' (défaut), 'agent' (personnel sur place), 'super_admin' (Mégane, créatrice).
-- La contrainte avait été créée inline dans add_backoffice.sql, Postgres l'a nommée profiles_role_check.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (role in ('usager', 'agent', 'super_admin'));

-- 2. Fonction équivalente à is_agent() (voir add_backoffice.sql) pour le rôle super_admin.
create or replace function public.is_super_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'super_admin'
  );
$$;

-- 3. is_agent() élargie pour inclure super_admin : un compte super_admin hérite donc
-- automatiquement de tous les accès agent existants (catalogue, réservations, agenda,
-- Bibliothèque Libre) sans avoir besoin d'un second rôle attribué à part.
create or replace function public.is_agent()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('agent', 'super_admin')
  );
$$;

-- 4. Commune de l'usager : choisie à l'inscription, confirmée ensuite par un agent/le
-- super-admin (ex. après vérification d'un justificatif de domicile en personne).
alter table public.profiles add column if not exists commune_id bigint references public.communes(id);
alter table public.profiles add column if not exists commune_confirmed boolean not null default false;

-- 5. Un super-admin voit et modifie tous les profils (pour confirmer une commune, changer
-- de rôle, etc.). Attention : Postgres RLS ne permet pas de restreindre l'UPDATE colonne
-- par colonne — cette policy autorise techniquement à modifier n'importe quel champ de
-- n'importe quel profil. Le rôle super_admin n'étant accordé qu'à Mégane, et le code JS de
-- superadmin.html ne devant jamais envoyer que { commune_id, commune_confirmed } (ou role,
-- pour se donner elle-même le rôle agent si besoin), le risque reste maîtrisé côté appli.
create policy "Un super-admin voit tous les profils"
  on public.profiles for select
  using (public.is_super_admin());

create policy "Un super-admin modifie tous les profils"
  on public.profiles for update
  using (public.is_super_admin());

-- 6. Gestion des communes (jusqu'ici lecture publique seulement, aucune écriture possible).
create policy "Un super-admin ajoute des communes"
  on public.communes for insert
  with check (public.is_super_admin());

create policy "Un super-admin modifie les communes"
  on public.communes for update
  using (public.is_super_admin());

create policy "Un super-admin supprime des communes"
  on public.communes for delete
  using (public.is_super_admin());

-- 7. handle_new_user() lit aussi la commune choisie à l'inscription (passée via
-- options.data.commune_id dans supabase.auth.signUp côté index.html).
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, subscriber_number, commune_id)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', 'Nouvel usager'),
    'VF-' || to_char(now(), 'YYYY') || '-' || lpad(floor(random() * 99999)::text, 5, '0'),
    nullif(new.raw_user_meta_data->>'commune_id', '')::bigint
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 8. Pour te donner le rôle super_admin (à faire une fois, manuellement) :
-- update public.profiles set role = 'super_admin' where subscriber_number = 'VF-2026-00001';
