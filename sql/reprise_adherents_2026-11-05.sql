-- Reprise des adhérents d'une médiathèque (05/11/2026, parcours validé par Mégane).
-- 1. La direction importe le fichier CSV de ses adhérents (Réglages > Données et export).
-- 2. L'adhérent crée son compte sur l'appli. Il est reconnu :
--    a) par son e-mail confirmé, s'il figure dans le fichier ;
--    b) sinon par son numéro de carte + sa date de naissance (5 essais par 24 h) ;
--    c) sinon au comptoir : il donne son nom, l'agent le retrouve et rattache son compte.
--    Jamais de rapprochement automatique sur le nom seul (homonymes).
-- Il garde alors son numéro de carte, sa catégorie et sa date de fin d'adhésion, sans justificatif.
-- Ré-exécutable sans danger. À exécuter dans Supabase (SQL Editor > New query > coller > Run).

create table if not exists public.adherents_importes (
  id bigint generated always as identity primary key,
  commune_id bigint not null references public.communes(id) on delete cascade,
  numero_carte text,
  nom_complet text not null,
  email text,
  date_naissance date,
  tariff_category text check (tariff_category is null or tariff_category in ('mineur', 'majeur', 'gratuit', 'famille')),
  adhesion_jusqu_au timestamptz,
  rattache_a uuid references auth.users(id) on delete set null,
  rattache_le timestamptz,
  importe_le timestamptz not null default now()
);
create unique index if not exists adherents_importes_carte_idx
  on public.adherents_importes (commune_id, numero_carte) where numero_carte is not null;
create index if not exists adherents_importes_email_idx
  on public.adherents_importes (commune_id, lower(email));

alter table public.adherents_importes enable row level security;
drop policy if exists "Les agents voient les adhérents importés de leur médiathèque" on public.adherents_importes;
create policy "Les agents voient les adhérents importés de leur médiathèque"
  on public.adherents_importes for select
  using (public.is_super_admin() or (public.is_agent() and public.agent_commune_id() = commune_id));

-- Essais par numéro de carte : limités pour empêcher de deviner une carte.
create table if not exists public.adherents_tentatives (
  user_id uuid not null references auth.users(id) on delete cascade,
  tente_le timestamptz not null default now()
);
create index if not exists adherents_tentatives_idx on public.adherents_tentatives (user_id, tente_le);
alter table public.adherents_tentatives enable row level security;

-- Prêts en cours repris d'un ancien logiciel : rattachés au compte dès qu'il est reconnu.
alter table public.loans add column if not exists adherent_importe_id bigint
  references public.adherents_importes(id) on delete set null;

-- ---------- Rattachement (interne) ----------
create or replace function public.appliquer_rattachement_adherent(p_adherent_id bigint, p_user_id uuid, p_agent uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_a public.adherents_importes;
  v_commune bigint;
begin
  select * into v_a from public.adherents_importes where id = p_adherent_id and rattache_a is null for update;
  if not found then raise exception 'Cet adhérent est déjà rattaché à un compte.'; end if;

  select commune_id into v_commune from public.profiles where id = p_user_id;

  update public.profiles
     set registration_status = 'valide',
         validated_at = now(),
         validated_by = p_agent,
         commune_id = coalesce(v_commune, v_a.commune_id),
         tariff_category = coalesce(v_a.tariff_category, tariff_category),
         membership_expires_at = coalesce(v_a.adhesion_jusqu_au, public.membership_expiry(v_a.commune_id, now())),
         membership_reminded_at = null,
         subscriber_number = case
           when v_a.numero_carte is not null
            and not exists (select 1 from public.profiles o where o.subscriber_number = v_a.numero_carte and o.id <> p_user_id)
           then v_a.numero_carte else subscriber_number end
   where id = p_user_id;

  update public.adherents_importes set rattache_a = p_user_id, rattache_le = now() where id = p_adherent_id;
  update public.loans set user_id = p_user_id where adherent_importe_id = p_adherent_id and user_id is null;

  insert into public.notifications (user_id, message)
  values (p_user_id, 'Bonne nouvelle ! Ton adhésion à la médiathèque est bien retrouvée. Ta carte est active et tu peux réserver directement.');

  perform public.log_activity('adherent_rattache', v_a.commune_id, 'adherent', p_adherent_id::text,
    jsonb_build_object('par_agent', p_agent is not null));
  return coalesce(v_a.numero_carte, '');
end;
$$;
revoke execute on function public.appliquer_rattachement_adherent(bigint, uuid, uuid) from public, anon, authenticated;

-- ---------- Côté usager ----------
-- Par e-mail : seulement si l'adresse est confirmée (code à 6 chiffres, Google ou Apple).
create or replace function public.reconnaitre_adherent()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_commune bigint;
  v_statut text;
  v_ids bigint[];
  v_fichier boolean;
begin
  if v_uid is null then return jsonb_build_object('statut', 'inconnu', 'fichier', false); end if;
  select commune_id, registration_status into v_commune, v_statut from public.profiles where id = v_uid;
  if v_statut is distinct from 'pre_inscrit' or v_commune is null then
    return jsonb_build_object('statut', 'inconnu', 'fichier', false);
  end if;
  -- « fichier » : l'appli ne propose « Déjà adhérent ? » que si la médiathèque a importé ses adhérents.
  v_fichier := exists (select 1 from public.adherents_importes where commune_id = v_commune and rattache_a is null);
  select lower(email) into v_email from auth.users where id = v_uid and email_confirmed_at is not null;
  if v_email is null then return jsonb_build_object('statut', 'inconnu', 'fichier', v_fichier); end if;

  select array_agg(id) into v_ids from public.adherents_importes
   where commune_id = v_commune and rattache_a is null and lower(email) = v_email;
  if v_ids is null then return jsonb_build_object('statut', 'inconnu', 'fichier', v_fichier); end if;
  -- Même e-mail sur plusieurs adhérents (famille) : on ne choisit pas à sa place.
  if array_length(v_ids, 1) > 1 then return jsonb_build_object('statut', 'plusieurs', 'fichier', true); end if;

  perform public.appliquer_rattachement_adherent(v_ids[1], v_uid, null);
  return jsonb_build_object('statut', 'reconnu');
end;
$$;
grant execute on function public.reconnaitre_adherent() to authenticated;

create or replace function public.reconnaitre_adherent_par_carte(p_numero text, p_naissance date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_commune bigint;
  v_statut text;
  v_id bigint;
  v_essais integer;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  select commune_id, registration_status into v_commune, v_statut from public.profiles where id = v_uid;
  if v_statut is distinct from 'pre_inscrit' or v_commune is null then
    return jsonb_build_object('statut', 'inconnu');
  end if;

  select count(*) into v_essais from public.adherents_tentatives
   where user_id = v_uid and tente_le > now() - interval '24 hours';
  if v_essais >= 5 then return jsonb_build_object('statut', 'trop_essais'); end if;
  insert into public.adherents_tentatives (user_id) values (v_uid);

  select id into v_id from public.adherents_importes
   where commune_id = v_commune and rattache_a is null
     and lower(numero_carte) = lower(trim(p_numero))
     and date_naissance = p_naissance;
  if v_id is null then return jsonb_build_object('statut', 'inconnu'); end if;

  perform public.appliquer_rattachement_adherent(v_id, v_uid, null);
  return jsonb_build_object('statut', 'reconnu');
end;
$$;
grant execute on function public.reconnaitre_adherent_par_carte(text, date) to authenticated;

-- ---------- Côté agent (comptoir) ----------
create or replace function public.chercher_adherent_importe(p_commune_id bigint, p_recherche text)
returns table (id bigint, numero_carte text, nom_complet text, adhesion_jusqu_au timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or (public.is_agent() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé aux agents de cette médiathèque';
  end if;
  return query
    select a.id, a.numero_carte, a.nom_complet, a.adhesion_jusqu_au
      from public.adherents_importes a
     where a.commune_id = p_commune_id and a.rattache_a is null
       and (a.nom_complet ilike '%' || trim(p_recherche) || '%' or a.numero_carte ilike trim(p_recherche) || '%')
     order by a.nom_complet
     limit 10;
end;
$$;
grant execute on function public.chercher_adherent_importe(bigint, text) to authenticated;

create or replace function public.rattacher_adherent_au_comptoir(p_user_id uuid, p_adherent_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commune bigint;
begin
  select commune_id into v_commune from public.adherents_importes where id = p_adherent_id;
  if not (public.is_super_admin() or (public.is_agent() and public.agent_commune_id() = v_commune)) then
    raise exception 'Réservé aux agents de cette médiathèque';
  end if;
  perform public.appliquer_rattachement_adherent(p_adherent_id, p_user_id, auth.uid());
end;
$$;
grant execute on function public.rattacher_adherent_au_comptoir(uuid, bigint) to authenticated;

-- ---------- Import (direction) ----------
-- Un nouvel import remplace les lignes pas encore rattachées ; les comptes déjà rattachés ne bougent pas.
create or replace function public.importer_adherents(p_commune_id bigint, p_lignes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  l jsonb;
  v_ok integer := 0;
  v_ignores integer := 0;
  v_n integer;
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;
  delete from public.adherents_importes where commune_id = p_commune_id and rattache_a is null;

  for l in select * from jsonb_array_elements(p_lignes) loop
    insert into public.adherents_importes
      (commune_id, numero_carte, nom_complet, email, date_naissance, tariff_category, adhesion_jusqu_au)
    values (
      p_commune_id,
      nullif(trim(l->>'numero_carte'), ''),
      trim(l->>'nom_complet'),
      nullif(lower(trim(l->>'email')), ''),
      nullif(l->>'date_naissance', '')::date,
      nullif(l->>'tariff_category', ''),
      nullif(l->>'adhesion_jusqu_au', '')::timestamptz
    )
    on conflict (commune_id, numero_carte) where numero_carte is not null do nothing;
    get diagnostics v_n = row_count;
    if v_n = 0 then v_ignores := v_ignores + 1; else v_ok := v_ok + 1; end if;
  end loop;

  perform public.log_activity('adherents_importes', p_commune_id, 'import', 'adherents',
    jsonb_build_object('importes', v_ok, 'ignores', v_ignores));
  return jsonb_build_object('importes', v_ok, 'ignores', v_ignores);
end;
$$;
grant execute on function public.importer_adherents(bigint, jsonb) to authenticated;

-- RGPD : retirer les adhérents qui n'ont pas créé de compte, une fois la reprise terminée.
create or replace function public.supprimer_adherents_non_rattaches(p_commune_id bigint)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n integer;
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;
  delete from public.adherents_importes where commune_id = p_commune_id and rattache_a is null;
  get diagnostics v_n = row_count;
  perform public.log_activity('adherents_supprimes', p_commune_id, 'import', 'adherents', jsonb_build_object('supprimes', v_n));
  return v_n;
end;
$$;
grant execute on function public.supprimer_adherents_non_rattaches(bigint) to authenticated;
