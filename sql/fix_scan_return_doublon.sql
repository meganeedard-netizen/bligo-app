-- 16/10/2026
-- « Marquer rendu » renvoyait : Could not choose the best candidate function
-- between scan_return(p_barcode) et scan_return(p_barcode, p_condition).
-- L'ancienne version à 1 paramètre (add_scan_operations.sql) est restée en base
-- quand add_commune_settings_and_flagging.sql a ajouté p_condition. La version
-- à 2 paramètres fait tout (état du livre, pénalité de retard) et accepte
-- p_condition vide : on supprime l'ancienne.

drop function if exists public.scan_return(text);

-- Vérification : doit renvoyer une seule ligne (p_barcode text, p_condition text)
select pg_get_function_identity_arguments(p.oid) as parametres
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'scan_return';
