-- Limites d'emprunt au comptoir et carte famille adultes / jeunesse (22/10/2026)
-- ============================================================
-- Avant : les limites de la médiathèque (documents, jeunesse, nouveautés)
-- s'appliquaient aux commandes de l'appli, pas aux prêts au comptoir ; la
-- carte famille n'avait qu'un plafond global. Maintenant :
--   - loan_limit_error() calcule, pour un usager et un livre, si une limite
--     est atteinte (prêts non rendus + commandes en cours) ;
--   - counter_checkout (Comptoir) et les commandes de l'appli l'utilisent ;
--   - la carte famille a deux plafonds : documents adultes et jeunesse ;
--   - la direction règle tout dans le logiciel (Réglages › Tarifs).

alter table public.communes add column if not exists family_max_general integer not null default 10;
alter table public.communes add column if not exists family_max_jeunesse integer not null default 10;

create or replace function public.loan_limit_error(p_user_id uuid, p_book_id bigint)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_category text;
  v_is_new boolean;
  v_is_jeunesse boolean;
  v_tariff text;
  v_commune public.communes;
  v_max integer;
  v_max_new integer;
  v_count integer;
  v_new_count integer;
begin
  select category, coalesce(is_new_release, false) into v_category, v_is_new from public.books where id = p_book_id;
  v_is_jeunesse := coalesce(v_category = 'Jeunesse', false);
  select tariff_category into v_tariff from public.profiles where id = p_user_id;
  select c.* into v_commune from public.communes c join public.profiles p on p.commune_id = c.id where p.id = p_user_id;

  if v_tariff = 'famille' then
    v_max := case when v_is_jeunesse then coalesce(v_commune.family_max_jeunesse, 10) else coalesce(v_commune.family_max_general, 10) end;
  else
    v_max := case when v_is_jeunesse then coalesce(v_commune.max_loans_jeunesse, 3) else coalesce(v_commune.max_loans_general, 3) end;
  end if;
  v_max_new := coalesce(v_commune.max_loans_new_releases, 1);

  select
    (select count(*) from public.reservations r join public.books b on b.id = r.book_id
      where r.user_id = p_user_id and r.status in ('panier', 'preparation', 'pret')
        and coalesce(b.category = 'Jeunesse', false) = v_is_jeunesse)
    + (select count(*) from public.loans l join public.book_copies c on c.id = l.copy_id join public.books b on b.id = c.book_id
        where l.user_id = p_user_id and l.returned_at is null
          and coalesce(b.category = 'Jeunesse', false) = v_is_jeunesse)
  into v_count;

  if v_count >= v_max then
    if v_tariff = 'famille' then
      return format('Limite de la carte famille atteinte : %s documents %s maximum à la fois.', v_max, case when v_is_jeunesse then 'jeunesse' else 'adultes' end);
    elsif v_is_jeunesse then
      return format('Limite atteinte : %s documents jeunesse maximum à la fois.', v_max);
    else
      return format('Limite atteinte : %s documents maximum à la fois.', v_max);
    end if;
  end if;

  if v_is_new then
    select
      (select count(*) from public.reservations r join public.books b on b.id = r.book_id
        where r.user_id = p_user_id and r.status in ('panier', 'preparation', 'pret') and coalesce(b.is_new_release, false))
      + (select count(*) from public.loans l join public.book_copies c on c.id = l.copy_id join public.books b on b.id = c.book_id
          where l.user_id = p_user_id and l.returned_at is null and coalesce(b.is_new_release, false))
    into v_new_count;
    if v_new_count >= v_max_new then
      return format('Limite atteinte : %s nouveauté(s) maximum à la fois.', v_max_new);
    end if;
  end if;

  return null;
end;
$$;

grant execute on function public.loan_limit_error(uuid, bigint) to authenticated;

-- Plafond global de la carte famille (encore vérifié par scan_checkout) :
-- la somme des deux plafonds, adultes + jeunesse.
create or replace function public.family_quota_reached(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*) from public.loans where user_id = p_user_id and returned_at is null)
    + (select count(*) from public.reservations where user_id = p_user_id and status in ('panier', 'preparation', 'pret'))
    >= (select coalesce(c.family_max_general, 10) + coalesce(c.family_max_jeunesse, 10)
          from public.profiles p join public.communes c on c.id = p.commune_id where p.id = p_user_id);
$$;

-- Réglage par la direction de la médiathèque (logiciel › Réglages › Tarifs).
create or replace function public.update_commune_loan_limits(
  p_commune_id bigint, p_max_general integer, p_max_jeunesse integer, p_max_new integer,
  p_family_general integer, p_family_jeunesse integer
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
  update public.communes
     set max_loans_general = greatest(1, coalesce(p_max_general, 3)),
         max_loans_jeunesse = greatest(0, coalesce(p_max_jeunesse, 3)),
         max_loans_new_releases = greatest(0, coalesce(p_max_new, 1)),
         family_max_general = greatest(1, coalesce(p_family_general, 10)),
         family_max_jeunesse = greatest(0, coalesce(p_family_jeunesse, 10))
   where id = p_commune_id;
end;
$$;

grant execute on function public.update_commune_loan_limits(bigint, integer, integer, integer, integer, integer) to authenticated;

-- Commandes de l'appli : la carte famille utilise ses deux plafonds
-- (le reste de la fonction est inchangé, reprise de add_panier_commande.sql).
create or replace function public.enforce_reservation_limits()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_category text;
  v_is_new_release boolean := false;
  v_is_jeunesse boolean;
  v_adult_only boolean := false;
  v_active_count integer;
  v_new_release_count integer;
  v_user_commune bigint;
  v_flagged boolean;
  v_tariff_category text;
  v_max_general integer;
  v_max_jeunesse integer;
  v_max_new_release integer;
  v_restricted_categories text[];
  v_blocks_new_release boolean;
  v_limit_error text;
begin
  if tg_table_name = 'reservations' then
    select category, coalesce(is_new_release, false), coalesce(adult_only, false)
    into v_category, v_is_new_release, v_adult_only
    from public.books where id = new.book_id;

    -- Même livre déjà dans le panier, en commande ou chez l'usager.
    if exists (
      select 1 from public.reservations r
      where r.user_id = new.user_id and r.book_id = new.book_id
        and r.status in ('panier', 'preparation', 'pret')
    ) or exists (
      select 1 from public.loans l join public.book_copies c on c.id = l.copy_id
      where l.user_id = new.user_id and c.book_id = new.book_id and l.returned_at is null
    ) then
      raise exception 'Tu as déjà ce livre dans ton panier, ta commande ou chez toi.';
    end if;
  else
    select category into v_category from public.free_books where id = new.free_book_id;
  end if;

  v_is_jeunesse := (v_category = 'Jeunesse');

  select commune_id, coalesce(flagged, false), tariff_category
  into v_user_commune, v_flagged, v_tariff_category
  from public.profiles where id = new.user_id;

  if v_tariff_category = 'mineur' and v_adult_only then
    raise exception 'Ce livre est réservé aux comptes majeurs.';
  end if;

  select
    coalesce(max_loans_general, 3), coalesce(max_loans_jeunesse, 3), coalesce(max_loans_new_releases, 1),
    coalesce(flagged_restricted_categories, '{}'), coalesce(flagged_blocks_new_releases, true)
  into v_max_general, v_max_jeunesse, v_max_new_release, v_restricted_categories, v_blocks_new_release
  from public.communes where id = v_user_commune;

  v_max_general := coalesce(v_max_general, 3);
  v_max_jeunesse := coalesce(v_max_jeunesse, 3);
  v_max_new_release := coalesce(v_max_new_release, 1);
  v_restricted_categories := coalesce(v_restricted_categories, '{}');
  v_blocks_new_release := coalesce(v_blocks_new_release, true);

  if v_flagged and v_category = any(v_restricted_categories) then
    raise exception 'Cet usager est actuellement restreint et ne peut pas emprunter dans la catégorie « % ».', v_category;
  end if;

  if v_flagged and v_blocks_new_release and v_is_new_release then
    raise exception 'Cet usager est actuellement restreint et ne peut pas emprunter les nouveautés.';
  end if;

  -- Carte famille (22/10/2026) : un plafond pour les documents adultes et un
  -- pour les documents jeunesse, réglés par la médiathèque.
  if v_tariff_category = 'famille' and tg_table_name = 'reservations' then
    v_limit_error := public.loan_limit_error(new.user_id, new.book_id);
    if v_limit_error is not null then
      raise exception '%', v_limit_error;
    end if;
    return new;
  end if;

  if tg_table_name = 'reservations' then
    select
      (select count(*)
         from public.reservations r
         join public.books b on b.id = r.book_id
        where r.user_id = new.user_id and r.status in ('panier', 'preparation', 'pret')
          and coalesce(b.category = 'Jeunesse', false) = coalesce(v_is_jeunesse, false))
      + (select count(*)
           from public.loans l
           join public.book_copies c on c.id = l.copy_id
           join public.books b on b.id = c.book_id
          where l.user_id = new.user_id and l.returned_at is null
            and coalesce(b.category = 'Jeunesse', false) = coalesce(v_is_jeunesse, false))
    into v_active_count;
  else
    select count(*) into v_active_count
    from public.free_book_loans l
    join public.free_books fb on fb.id = l.free_book_id
    where l.user_id = new.user_id and l.status in ('preparation', 'pret')
      and coalesce(fb.category = 'Jeunesse', false) = coalesce(v_is_jeunesse, false);
  end if;

  if v_is_jeunesse then
    if v_active_count >= v_max_jeunesse then
      raise exception 'Limite atteinte : % documents jeunesse maximum à la fois (panier, commande et emprunts compris).', v_max_jeunesse;
    end if;
  elsif tg_table_name = 'reservations' then
    if v_active_count >= v_max_general then
      raise exception 'Limite atteinte : % documents maximum à la fois (panier, commande et emprunts compris).', v_max_general;
    end if;
  else
    if v_active_count >= v_max_general then
      raise exception 'Limite atteinte : % livres hors condition maximum en cours à la fois (hors jeunesse). Rapporte-en un pour en prendre un nouveau.', v_max_general;
    end if;
  end if;

  if v_is_new_release and tg_table_name = 'reservations' then
    select
      (select count(*)
         from public.reservations r
         join public.books b on b.id = r.book_id
        where r.user_id = new.user_id and r.status in ('panier', 'preparation', 'pret') and coalesce(b.is_new_release, false))
      + (select count(*)
           from public.loans l
           join public.book_copies c on c.id = l.copy_id
           join public.books b on b.id = c.book_id
          where l.user_id = new.user_id and l.returned_at is null and coalesce(b.is_new_release, false))
    into v_new_release_count;

    if v_new_release_count >= v_max_new_release then
      raise exception 'Limite atteinte : % nouveauté(s) maximum à la fois.', v_max_new_release;
    end if;
  end if;

  return new;
end;
$$;

-- Comptoir : les limites s'appliquent aussi au prêt
-- (reprise de add_counter_checkout.sql, avec le contrôle des limites).
create or replace function public.counter_checkout(p_barcode text, p_subscriber_number text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_copy public.book_copies;
  v_user uuid;
  v_resa bigint;
  v_others integer;
  v_reserved integer;
  v_free integer;
  v_result jsonb;
  v_loan bigint;
  v_limit_error text;
begin
  if not (public.is_agent() or public.is_super_admin()) then
    raise exception 'Accès réservé aux agents';
  end if;

  select * into v_copy from public.book_copies where barcode = trim(p_barcode);
  select id into v_user from public.profiles where subscriber_number = trim(p_subscriber_number);
  -- Code-barres ou usager inconnu : scan_checkout renvoie le bon message.
  if v_copy.id is null or v_user is null then
    return public.scan_checkout(p_barcode, p_subscriber_number);
  end if;

  -- Commande de cet usager pour ce livre (en préparation ou prête).
  select r.id into v_resa from public.reservations r
   where r.book_id = v_copy.book_id and r.user_id = v_user and r.status in ('preparation', 'pret')
   order by r.created_at limit 1;

  -- Exemplaire en rayon, mais tous les exemplaires libres sont promis à des
  -- commandes d'autres usagers (les exemplaires déjà mis de côté couvrent
  -- chacun une commande).
  if v_resa is null and v_copy.status = 'available' then
    select count(*) into v_others from public.reservations r
     where r.book_id = v_copy.book_id and r.user_id <> v_user and r.status in ('preparation', 'pret');
    select count(*) into v_reserved from public.book_copies where book_id = v_copy.book_id and status = 'reserved';
    select count(*) into v_free from public.book_copies where book_id = v_copy.book_id and status = 'available';
    if v_others - v_reserved >= v_free then
      return jsonb_build_object('ok', false, 'ordered_by_other', true,
        'message', 'Ce livre est commandé par un autre usager dans l''appli (commande en préparation ou prête) : il ne peut pas être prêté.');
    end if;
  end if;

  -- Limites de la médiathèque (22/10/2026) : documents adultes, jeunesse,
  -- nouveautés, et plafonds propres à la carte famille. Le livre qu'il avait
  -- déjà commandé est déjà compté.
  if v_resa is null then
    v_limit_error := public.loan_limit_error(v_user, v_copy.book_id);
    if v_limit_error is not null then
      return jsonb_build_object('ok', false, 'limit_reached', true, 'message', v_limit_error);
    end if;
  end if;

  v_result := public.scan_checkout(p_barcode, p_subscriber_number);

  -- Prêt du livre qu'il avait commandé : la commande est récupérée.
  if coalesce((v_result->>'ok')::boolean, false) and v_resa is not null then
    select id into v_loan from public.loans
     where copy_id = v_copy.id and returned_at is null order by borrowed_at desc limit 1;
    update public.loans set reservation_id = v_resa where id = v_loan and reservation_id is null;
    update public.reservations
       set status = 'recupere', return_due_at = coalesce((v_result->>'due_at')::timestamptz, return_due_at)
     where id = v_resa and status in ('preparation', 'pret');
    v_result := v_result || jsonb_build_object('from_reservation', true);
  end if;

  return v_result;
end;
$$;

-- Vérification : doit renvoyer les 5 fonctions.
select proname from pg_proc where proname in ('loan_limit_error', 'family_quota_reached', 'update_commune_loan_limits', 'enforce_reservation_limits', 'counter_checkout') order by proname;
