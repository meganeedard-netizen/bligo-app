-- BliGO, 25/11/2026 (demande de Mégane) : à l'inscription, majeur ou mineur, âge
-- précis du mineur, carte famille (1 ou 2 adultes, âge de chaque enfant).
-- Âges seulement, jamais de date de naissance ni de prénom d'enfant (RGPD).
-- L'âge vieillit tout seul : âge déclaré + années entières écoulées.
alter table public.profiles add column if not exists declared_age smallint check (declared_age between 0 and 17);
alter table public.profiles add column if not exists declared_on date;
alter table public.profiles add column if not exists family_adults smallint check (family_adults between 1 and 2);
alter table public.profiles add column if not exists family_children smallint[];

create or replace function public.declare_my_profile(p_category text, p_age integer default null, p_adults integer default null, p_children integer[] default null)
returns void language plpgsql security definer set search_path = public as $$
declare c integer;
begin
  if p_category is null or p_category not in ('majeur', 'mineur', 'famille') then raise exception 'Catégorie invalide.'; end if;
  if p_category = 'mineur' and (p_age is null or p_age < 0 or p_age > 17) then raise exception 'Indique ton âge (17 ans au plus).'; end if;
  if p_category = 'famille' then
    if p_adults is null or p_adults not in (1, 2) then raise exception 'Indique 1 ou 2 adultes.'; end if;
    if coalesce(array_length(p_children, 1), 0) not between 1 and 10 then raise exception 'Indique de 1 à 10 enfants.'; end if;
    foreach c in array p_children loop
      if c is null or c < 0 or c > 17 then raise exception 'Indique l''âge de chaque enfant (17 ans au plus).'; end if;
    end loop;
  end if;
  update public.profiles set
    tariff_category = p_category,
    declared_age = case when p_category = 'mineur' then p_age end,
    declared_on = case when p_category in ('mineur', 'famille') then current_date end,
    family_adults = case when p_category = 'famille' then p_adults end,
    family_children = case when p_category = 'famille' then p_children::smallint[] end
  where id = auth.uid() and role = 'usager' and coalesce(registration_status, 'pre_inscrit') <> 'valide';
  if not found then raise exception 'Ton inscription est déjà validée : demande la modification à ta médiathèque.'; end if;
end $$;
revoke all on function public.declare_my_profile(text, integer, integer, integer[]) from public, anon;
grant execute on function public.declare_my_profile(text, integer, integer, integer[]) to authenticated;

create or replace function public.age_block_message(p_user uuid, p_book bigint)
returns text language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_min integer; v_rating text; v_year integer; v_tariff text; v_age integer; v_declared integer; v_on date;
begin
  select coalesce(min_age, case when adult_only then 18 end), age_rating into v_min, v_rating from public.books where id = p_book;
  if coalesce(v_min, 0) = 0 then return null; end if;
  select birth_year, tariff_category, declared_age, declared_on into v_year, v_tariff, v_declared, v_on from public.profiles where id = p_user;
  v_age := public.reader_min_age(v_year, v_tariff);
  -- L'année saisie par la médiathèque l'emporte sur l'âge déclaré.
  if v_age is null and v_tariff = 'mineur' and v_declared is not null then
    v_age := v_declared + extract(year from age(current_date, v_on))::int;
  end if;
  if (v_age is not null and v_age < v_min) or (v_age is null and v_tariff = 'mineur' and v_min >= 16) then
    return 'Ce document est réservé aux ' || v_min || ' ans et plus' || coalesce(' (' || v_rating || ')', '') || '.';
  end if;
  return null;
end $function$;
