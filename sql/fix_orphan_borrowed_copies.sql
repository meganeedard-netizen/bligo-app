-- 12/10/2026
-- Exemplaires marqués « Emprunté » sans aucun prêt en cours.
-- Constaté sur Val-Fleuri : 12 exemplaires bloqués en « Emprunté » alors
-- qu'aucun prêt ne correspond. Cause la plus probable : un prêt supprimé
-- (ex. compte usager de test supprimé, les prêts partent avec lui) sans que
-- l'exemplaire soit remis en rayon. Résultat : le livre apparaît
-- indisponible dans l'appli et au catalogue, alors qu'il est sur l'étagère.

-- 1. Remise en rayon des exemplaires bloqués
update public.book_copies c
   set status = 'available'
 where c.status = 'borrowed'
   and not exists (
     select 1 from public.loans l
      where l.copy_id = c.id and l.returned_at is null
   );

-- 2. Pour l'avenir : si un prêt en cours est supprimé, l'exemplaire
--    redevient disponible au lieu de rester bloqué.
create or replace function public.release_copy_on_loan_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.returned_at is null then
    update public.book_copies
       set status = 'available'
     where id = old.copy_id
       and status = 'borrowed'
       and not exists (
         select 1 from public.loans l
          where l.copy_id = old.copy_id and l.returned_at is null and l.id <> old.id
       );
  end if;
  return old;
end;
$$;

drop trigger if exists trg_release_copy_on_loan_delete on public.loans;
create trigger trg_release_copy_on_loan_delete
  after delete on public.loans
  for each row execute function public.release_copy_on_loan_delete();

-- Vérification : doit renvoyer 0
select count(*) as exemplaires_encore_bloques
  from public.book_copies c
 where c.status = 'borrowed'
   and not exists (select 1 from public.loans l where l.copy_id = c.id and l.returned_at is null);
