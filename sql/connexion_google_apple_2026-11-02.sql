-- BliGO - « Continuer avec Google » et « Continuer avec Apple » (02/11/2026)
--
-- Un compte créé par Google ou Apple n'a pas les informations du formulaire
-- d'inscription (médiathèque, prénom, nom) dans ses métadonnées. Sans ce
-- fichier, handle_new_user en faisait un compte « libre » déjà validé, sans
-- médiathèque. Maintenant : compte officiel préinscrit comme les autres,
-- rattaché ensuite à la médiathèque choisie dans l'appli
-- (rattacher_ma_mediatheque), adresse e-mail considérée comme vérifiée
-- (Google et Apple l'ont déjà vérifiée).

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $function$
declare
  v_social boolean := coalesce(new.raw_app_meta_data->>'provider', 'email') in ('google', 'apple');
  v_account_type text := case when v_social or new.raw_user_meta_data->>'account_type' = 'officiel' then 'officiel' else 'libre' end;
  v_commune_id bigint := nullif(new.raw_user_meta_data->>'commune_id', '')::bigint;
  v_self_declared text := nullif(new.raw_user_meta_data->>'self_declared_category', '');
begin
  insert into public.profiles (id, full_name, subscriber_number, account_type, commune_id, registration_status, tariff_category, email_verifie)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), nullif(new.raw_user_meta_data->>'name', ''), 'Nouvel usager'),
    'VF-' || to_char(now(), 'YYYY') || '-' || lpad(floor(random() * 99999)::text, 5, '0'),
    v_account_type,
    case when v_account_type = 'officiel' then v_commune_id else null end,
    case when v_account_type = 'officiel' then 'pre_inscrit' else 'valide' end,
    case when v_self_declared in ('mineur', 'majeur') then v_self_declared else null end,
    v_social
  );
  return new;
end;
$function$;

-- Juste après une première connexion Google/Apple : la médiathèque choisie
-- sur l'écran d'accueil. Seulement si le compte n'en a pas encore.
create or replace function public.rattacher_ma_mediatheque(p_commune_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Non connecté';
  end if;
  if not exists (select 1 from public.communes where id = p_commune_id) then
    raise exception 'Médiathèque inconnue';
  end if;
  update public.profiles set commune_id = p_commune_id
  where id = auth.uid() and commune_id is null and account_type = 'officiel' and role = 'usager';
  return found;
end;
$$;

grant execute on function public.rattacher_ma_mediatheque(bigint) to authenticated;

-- Compte déjà créé avec e-mail + mot de passe, puis connexion par Google ou
-- Apple avec la même adresse : la connexion prouve aussi l'adresse.
create or replace function public.confirmer_mon_email()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Non connecté';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(coalesce(auth.jwt()->'amr', '[]'::jsonb)) a
    where a->>'method' in ('otp', 'magiclink', 'recovery', 'oauth', 'id_token')
  ) then
    raise exception 'Code de vérification manquant';
  end if;
  update public.profiles set email_verifie = true where id = auth.uid();
  return true;
end;
$$;
