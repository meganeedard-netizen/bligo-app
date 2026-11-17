-- Réseau de démonstration (prêt à 2 niveaux) : réseau, BDP, 3 bibliothèques, livres et exemplaires
-- Les livres sont copiés depuis le catalogue de Val-Fleuri (couvertures comprises).
-- Noms de communes INVENTÉS. Réseau marqué is_demo : invisible pour les vrais comptes.
do $$
declare
  v_net bigint; v_bdp bigint; v_ma bigint; v_vr bigint; v_pb bigint;
  v_cols text; v_lib bigint; v_n int := 0; v_book bigint; b record; v_i int;
begin
  if exists (select 1 from public.communities where is_demo) then
    raise exception 'Le réseau de démo existe déjà';
  end if;

  insert into public.communities (name, lending_scope, returns_anywhere, transfers_enabled, loan_duration_days,
                                  navette_next_date, navette_label, depot_recall_min_days, is_demo)
  values ('Réseau départemental de démonstration', 'community', true, true, 21,
          date '2026-12-01', 'Navette mensuelle', 30, true)
  returning id into v_net;

  -- Communes : mêmes réglages que Val-Fleuri, sauf nom, réseau, logo, BDP
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'communes'
    and column_name not in ('id', 'name', 'created_at', 'community_id', 'logo_url', 'is_bdp',
                            'agenda_digest_last_at', 'address', 'tariff_updated_at', 'tariff_updated_by');

  execute format('insert into public.communes (name, community_id, is_bdp, address, %s)
                  select $1, $2, $3, $4, %s from public.communes where id = 1 returning id', v_cols, v_cols)
    using 'Bibliothèque départementale (démo)', v_net, true, 'Zone d''activités, 20000 Démonstration' into v_bdp;
  execute format('insert into public.communes (name, community_id, is_bdp, address, %s)
                  select $1, $2, $3, $4, %s from public.communes where id = 1 returning id', v_cols, v_cols)
    using 'Monte-Alto', v_net, false, 'Place de l''Église, Monte-Alto' into v_ma;
  execute format('insert into public.communes (name, community_id, is_bdp, address, %s)
                  select $1, $2, $3, $4, %s from public.communes where id = 1 returning id', v_cols, v_cols)
    using 'Valle-Rossa', v_net, false, 'Rue de la Mairie, Valle-Rossa' into v_vr;
  execute format('insert into public.communes (name, community_id, is_bdp, address, %s)
                  select $1, $2, $3, $4, %s from public.communes where id = 1 returning id', v_cols, v_cols)
    using 'Pietra-Bianca', v_net, false, 'Ancienne école, Pietra-Bianca' into v_pb;

  -- Livres : 40 pour la BDP, 12 pour chaque bibliothèque (pris dans le catalogue de Val-Fleuri)
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'books'
    and column_name not in ('id', 'created_at', 'commune_id', 'available', 'archived');

  for b in select id from public.books where commune_id = 1 and not coalesce(archived, false)
           and cover_url is not null order by id limit 76 loop
    v_n := v_n + 1;
    v_lib := case when v_n <= 40 then v_bdp
                  when v_n <= 52 then v_ma
                  when v_n <= 64 then v_vr
                  else v_pb end;
    execute format('insert into public.books (commune_id, available, archived, %s)
                    select $1, true, false, %s from public.books where id = $2 returning id', v_cols, v_cols)
      using v_lib, b.id into v_book;
    -- 1 exemplaire (2 pour un livre sur 4 de la BDP)
    for v_i in 1 .. (case when v_lib = v_bdp and v_n % 4 = 0 then 2 else 1 end) loop
      insert into public.book_copies (book_id, barcode, owner_commune_id, current_commune_id, shelf_location, status, condition, acquired_at, source)
      select v_book,
             'DEMO-' || case when v_lib = v_bdp then 'BDP' when v_lib = v_ma then 'MA' when v_lib = v_vr then 'VR' else 'PB' end
               || '-' || lpad((v_n * 10 + v_i)::text, 4, '0'),
             v_lib, v_lib, bk.shelf_location, 'available', 'bon', date '2026-01-15', 'purchase'
      from public.books bk where bk.id = v_book;
    end loop;
  end loop;

  raise notice 'reseau=% bdp=% monte_alto=% valle_rossa=% pietra_bianca=%', v_net, v_bdp, v_ma, v_vr, v_pb;
end $$;

select cm.id, cm.name, cm.is_bdp,
       (select count(*) from public.books b where b.commune_id = cm.id) as livres,
       (select count(*) from public.book_copies c where c.owner_commune_id = cm.id) as exemplaires
from public.communes cm join public.communities co on co.id = cm.community_id
where co.is_demo order by cm.id;
