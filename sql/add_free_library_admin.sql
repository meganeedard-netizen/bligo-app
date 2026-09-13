-- À exécuter dans Supabase (SQL Editor > New query > coller > Run)
-- Permet aux agents (back-office) d'ajouter un livre à la Bibliothèque Libre
-- (utilisé quand un livre scanné est jugé trop abîmé pour le catalogue officiel).

create policy "Un agent ajoute des livres à la Bibliothèque Libre"
  on public.free_books for insert
  with check (public.is_agent());
