-- Mes réservations en temps réel (22/10/2026)
-- ============================================================
-- La page Mes réservations de l'appli s'abonne aux changements de ses
-- commandes, prêts et files d'attente : quand l'agent prépare, remet un livre
-- ou enregistre un retour, l'usager le voit tout de suite sans recharger.
-- Les règles d'accès s'appliquent : chacun ne reçoit que ses propres lignes.

do $$
begin
  begin alter publication supabase_realtime add table public.reservations; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.loans; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.holds; exception when duplicate_object then null; end;
end $$;

-- Vérification : doit renvoyer holds, loans, reservations.
select tablename from pg_publication_tables
 where pubname = 'supabase_realtime' and tablename in ('reservations', 'loans', 'holds')
 order by tablename;
