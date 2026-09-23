-- BliGO — Personnalisation de l'interface par médiathèque (22/09/2026)
-- ============================================================
-- Chaque médiathèque peut remplacer son propre logo et les deux teintes
-- principales (le vert "ink" et le dégradé orange/hibiscus, devenu un
-- dégradé dans UNE seule couleur choisie) — appliqué à l'appli usager ET au
-- logiciel agent (utile pour les démos commerciales auprès des médiathèques,
-- demandé le 23/09/2026), jamais à l'espace super admin.

alter table public.communes add column if not exists theme_ink_hex text;
alter table public.communes add column if not exists theme_accent_hex text;
alter table public.communes add column if not exists logo_url text;

comment on column public.communes.theme_ink_hex is 'Couleur de texte/fond principale (remplace le vert #1B4B43 par défaut), hex #RRGGBB. Null = couleur BliGO par défaut.';
comment on column public.communes.theme_accent_hex is 'Couleur de base du dégradé (remplace orange/hibiscus par un dégradé dans cette seule teinte), hex #RRGGBB. Null = dégradé BliGO par défaut.';
comment on column public.communes.logo_url is 'Logo de la médiathèque, affiché à la place de celui de BliGO côté usager.';

create or replace function public.update_commune_theme(
  p_commune_id bigint, p_ink_hex text, p_accent_hex text, p_logo_url text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;

  if p_ink_hex is not null and p_ink_hex !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Couleur invalide : %', p_ink_hex;
  end if;
  if p_accent_hex is not null and p_accent_hex !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Couleur invalide : %', p_accent_hex;
  end if;

  update public.communes
    set theme_ink_hex = p_ink_hex,
        theme_accent_hex = p_accent_hex,
        logo_url = coalesce(p_logo_url, logo_url)
    where id = p_commune_id;
end;
$$;

-- Si cet insert est refusé par l'éditeur SQL de ton projet Supabase (rare, selon le plan),
-- crée le bucket à la main : Dashboard > Storage > New bucket > nom "commune-logos" > Public ON,
-- puis exécute seulement les 3 "create policy" ci-dessous.
insert into storage.buckets (id, name, public)
values ('commune-logos', 'commune-logos', true)
on conflict (id) do nothing;

create policy "Lecture publique des logos de médiathèque"
  on storage.objects for select
  using (bucket_id = 'commune-logos');

-- Chemin attendu : "<commune_id>/logo.<ext>" — la direction ne dépose que
-- dans le dossier de sa propre médiathèque, jamais celui d'une autre.
create policy "La direction dépose le logo de sa médiathèque"
  on storage.objects for insert
  with check (
    bucket_id = 'commune-logos'
    and public.is_direction()
    and (storage.foldername(name))[1] = public.agent_commune_id()::text
  );

create policy "La direction remplace le logo de sa médiathèque"
  on storage.objects for update
  using (
    bucket_id = 'commune-logos'
    and public.is_direction()
    and (storage.foldername(name))[1] = public.agent_commune_id()::text
  )
  with check (
    bucket_id = 'commune-logos'
    and public.is_direction()
    and (storage.foldername(name))[1] = public.agent_commune_id()::text
  );
