-- BliGO : impression d'étiquettes code-barres d'exemplaire (18/11/2026,
-- suite au RDV des Abymes : 2 054 € payés une année pour douchettes + étiquettes).
--
-- Chaque médiathèque a sa numérotation : préfixe + numéro sur N chiffres
-- (ex. ABY00001234). Un compteur réserve les numéros au moment de l'impression :
-- deux agents qui impriment en même temps n'auront jamais le même code, et un
-- code déjà présent dans le catalogue (fonds importé, autre médiathèque) est sauté.

alter table public.communes add column if not exists barcode_prefix text;
alter table public.communes add column if not exists barcode_digits integer not null default 8;
alter table public.communes add column if not exists barcode_next bigint not null default 1;
alter table public.communes drop constraint if exists communes_barcode_digits_check;
alter table public.communes add constraint communes_barcode_digits_check check (barcode_digits between 4 and 14);
alter table public.communes drop constraint if exists communes_barcode_prefix_check;
alter table public.communes add constraint communes_barcode_prefix_check
  check (barcode_prefix is null or (barcode_prefix ~ '^[A-Z0-9-]{0,8}$' and barcode_prefix !~* '^BLIGO'));

-- Réglage par la direction (Réglages > Étiquettes code-barres).
create or replace function public.set_barcode_settings(p_prefix text, p_digits integer, p_next bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_direction() or public.is_super_admin()) then
    raise exception 'Réservé à la direction';
  end if;
  if upper(coalesce(p_prefix, '')) ~ '^BLIGO' then
    raise exception 'Le préfixe BLIGO est réservé aux codes provisoires.';
  end if;
  update public.communes
     set barcode_prefix = nullif(upper(trim(coalesce(p_prefix, ''))), ''),
         barcode_digits = p_digits,
         barcode_next = greatest(1, p_next)
   where id = public.agent_commune_id();
end;
$$;

-- Prochain numéro conseillé : le plus grand numéro déjà utilisé avec ce
-- préfixe et cette longueur, + 1 (pour reprendre après un fonds importé).
create or replace function public.barcode_next_suggestion(p_prefix text, p_digits integer)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(max(substr(barcode, length(coalesce(p_prefix, '')) + 1)::bigint), 0) + 1
    from public.book_copies
   where public.is_agent()
     and barcode ~ ('^' || coalesce(p_prefix, '') || '[0-9]{' || p_digits || '}$');
$$;

-- Réserve p_count codes à la suite pour la médiathèque de l'agent.
create or replace function public.reserve_library_barcodes(p_count integer)
returns setof text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_commune bigint := public.agent_commune_id();
  v_prefix text;
  v_digits integer;
  v_n bigint;
  v_code text;
  v_done integer := 0;
  v_guard integer := 0;
begin
  if not public.is_agent() then
    raise exception 'Réservé aux agents.';
  end if;
  if p_count is null or p_count < 1 or p_count > 1000 then
    raise exception 'Entre 1 et 1 000 étiquettes à la fois.';
  end if;

  select coalesce(barcode_prefix, ''), barcode_digits, barcode_next
    into v_prefix, v_digits, v_n
    from public.communes where id = v_commune
   for update;

  while v_done < p_count loop
    v_guard := v_guard + 1;
    if v_guard > p_count + 100000 then
      raise exception 'Trop de numéros déjà utilisés : change le prochain numéro dans les réglages.';
    end if;
    if length(v_n::text) > v_digits then
      raise exception 'Plus de numéros disponibles sur % chiffres : augmente le nombre de chiffres dans les réglages.', v_digits;
    end if;
    v_code := v_prefix || lpad(v_n::text, v_digits, '0');
    v_n := v_n + 1;
    if not exists (select 1 from public.book_copies where barcode = v_code) then
      v_done := v_done + 1;
      return next v_code;
    end if;
  end loop;

  update public.communes set barcode_next = v_n where id = v_commune;
end;
$$;

grant execute on function public.set_barcode_settings(text, integer, bigint) to authenticated;
grant execute on function public.barcode_next_suggestion(text, integer) to authenticated;
grant execute on function public.reserve_library_barcodes(integer) to authenticated;
