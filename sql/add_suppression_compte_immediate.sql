-- Suppression immédiate de son compte par l'usager, depuis l'appli (23/10/2026).
-- Remplace la demande par e-mail « traitée sous un mois ». Apple exige que la
-- suppression se fasse dans l'appli (règle 5.1.1 v).
--
-- Conditions : aucun document en cours d'emprunt et aucune dette ouverte
-- (document perdu ou abîmé non réglé). Sinon, message clair et rien n'est supprimé.
--
-- Ce qui disparaît : le compte de connexion, le profil, et tout ce qui est
-- rattaché à l'usager avec « on delete cascade » (emprunts rendus, réservations,
-- liste d'envie, avis, inscriptions aux événements...).
-- Les autres traces où le compte apparaît (ex. « parrainé par », « don de »)
-- sont vidées (mises à null) pour ne pas bloquer la suppression.

create or replace function public.delete_my_account()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
  fk record;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'message', 'Tu dois être connecté pour supprimer ton compte.');
  end if;

  -- Les comptes agents et administrateurs ne se suppriment pas depuis l'appli.
  if exists (select 1 from public.profiles where id = uid and role in ('agent', 'super_admin')) then
    return jsonb_build_object('ok', false, 'message', 'Un compte agent ne peut pas être supprimé depuis l''appli. Écris-nous à megane@bligo.fr.');
  end if;

  if exists (select 1 from public.loans where user_id = uid and returned_at is null) then
    return jsonb_build_object('ok', false, 'message', 'Tu as encore des documents empruntés. Rends-les à la médiathèque, puis tu pourras supprimer ton compte.');
  end if;

  if exists (select 1 from public.document_debts where user_id = uid and status = 'open') then
    return jsonb_build_object('ok', false, 'message', 'Un document perdu ou abîmé reste à régler avec la médiathèque. Une fois réglé, tu pourras supprimer ton compte.');
  end if;

  -- Toutes les colonnes qui pointent vers le compte sans « on delete cascade » :
  -- mises à null (ou lignes supprimées si la colonne est obligatoire).
  for fk in
    select c.conrelid::regclass as tbl, a.attname as col, a.attnotnull as notnull
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f'
      and c.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass)
      and c.confdeltype <> 'c'
      and array_length(c.conkey, 1) = 1
      and c.conrelid::regclass::text not like 'auth.%'
  loop
    if fk.notnull then
      execute format('delete from %s where %I = $1', fk.tbl, fk.col) using uid;
    else
      execute format('update %s set %I = null where %I = $1', fk.tbl, fk.col, fk.col) using uid;
    end if;
  end loop;

  delete from public.profiles where id = uid;
  delete from auth.users where id = uid;

  return jsonb_build_object('ok', true, 'message', 'Ton compte a été supprimé.');
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
