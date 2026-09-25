-- Permet à un agent de corriger le nom/prénom d'un usager depuis sa fiche
-- (erreur de saisie à l'inscription, ou différence constatée avec la pièce
-- d'identité au retrait de la première commande). Même logique que
-- set_tariff_category : saisie de routine, pas une action sensible.

create or replace function public.update_usager_name(p_user_id uuid, p_full_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;
  if trim(coalesce(p_full_name, '')) = '' then
    raise exception 'Le nom ne peut pas être vide';
  end if;

  update public.profiles set full_name = trim(p_full_name) where id = p_user_id;
end;
$$;
