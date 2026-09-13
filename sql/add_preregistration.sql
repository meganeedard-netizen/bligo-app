-- Pré-inscription des usagers : à la création de son compte, un usager est
-- "pré-inscrit". Sa carte (numéro d'abonné + QR code) ne devient active qu'après
-- validation par un agent de la médiathèque, en personne, après vérification
-- d'une pièce d'identité et d'un justificatif de domicile.

alter table public.profiles
  add column if not exists registration_status text not null default 'pre_inscrit'
    check (registration_status in ('pre_inscrit', 'valide'));

alter table public.profiles
  add column if not exists validated_at timestamptz;

alter table public.profiles
  add column if not exists validated_by uuid references auth.users(id);

-- Un agent valide une pré-inscription après avoir vérifié les documents sur
-- place. Passe par une fonction (plutôt qu'une policy d'update ouverte sur
-- profiles) pour ne permettre de ne toucher que les champs de validation,
-- et notifier l'usager au passage.
create or replace function public.validate_registration(p_user_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  if not public.is_agent() then
    raise exception 'Seul un agent peut valider une inscription.';
  end if;

  update public.profiles
  set registration_status = 'valide',
      validated_at = now(),
      validated_by = auth.uid()
  where id = p_user_id;

  insert into public.notifications (user_id, message)
  values (p_user_id, 'Votre inscription a été validée par la médiathèque ! Votre carte et votre QR code sont maintenant actifs dans votre profil.');
end;
$$;

grant execute on function public.validate_registration(uuid) to authenticated;
