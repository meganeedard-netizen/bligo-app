-- À exécuter dans Supabase (SQL Editor > New query > coller > Run)
-- Permet aux agents (back-office) d'ajouter, modifier et supprimer des
-- événements dans l'agenda culturel (table déjà créée par add_points_and_agenda.sql).
-- Réutilise la fonction is_agent() créée par add_backoffice.sql.

create policy "Un agent ajoute des événements"
  on public.events for insert
  with check (public.is_agent());

create policy "Un agent modifie les événements"
  on public.events for update
  using (public.is_agent());

create policy "Un agent supprime des événements"
  on public.events for delete
  using (public.is_agent());
