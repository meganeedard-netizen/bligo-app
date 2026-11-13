-- BliGO : données pour le rapport Néoscrib (13/11/2026, suite)
-- ============================================================
-- Ce qui manquait pour remplir l'enquête automatiquement :
-- 1. Tranche d'âge de l'usager (0-14 / 15-64 / 65 ans et plus), cochée par
--    l'agent à la validation de l'inscription. Pas de date de naissance.
-- 2. Habite la commune (ou le réseau) : oui / non.
-- 3. Compte collectivité (classe, crèche, maison de retraite...).
-- 4. Exemplaires en dépôt de la bibliothèque départementale : nouvelle
--    provenance « depot_bd » (à côté d'achat et don).
-- 5. Événements : public visé (tous publics / enfants) et nombre de
--    participants saisi après coup.
-- Puis neoscrib_auto est recalculée avec tout ça (voir
-- add_neoscrib_rapport_annuel.sql pour la version précédente).

alter table public.profiles add column if not exists age_group text;
alter table public.profiles drop constraint if exists profiles_age_group_check;
alter table public.profiles add constraint profiles_age_group_check
  check (age_group is null or age_group in ('enfant', 'adulte', 'senior'));
alter table public.profiles add column if not exists resident boolean;
alter table public.profiles add column if not exists is_collectivite boolean not null default false;

alter table public.book_copies drop constraint if exists book_copies_source_check;
alter table public.book_copies add constraint book_copies_source_check
  check (source in ('purchase', 'donation', 'depot_bd'));

alter table public.events add column if not exists audience text not null default 'tous';
alter table public.events drop constraint if exists events_audience_check;
alter table public.events add constraint events_audience_check check (audience in ('tous', 'enfants'));
alter table public.events add column if not exists participants integer;

-- Un agent de la médiathèque de l'usager règle ces trois informations.
create or replace function public.set_usager_neoscrib(
  p_user_id uuid, p_age_group text, p_resident boolean, p_collectivite boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or (public.is_agent() and exists (
    select 1 from public.profiles p where p.id = p_user_id and p.commune_id = public.agent_commune_id()))) then
    raise exception 'Réservé aux agents de la médiathèque de cet usager';
  end if;
  if p_age_group is not null and p_age_group not in ('enfant', 'adulte', 'senior') then
    raise exception 'Tranche d''âge inconnue';
  end if;
  update public.profiles
     set age_group = p_age_group, resident = p_resident, is_collectivite = coalesce(p_collectivite, false)
   where id = p_user_id;
end;
$$;
grant execute on function public.set_usager_neoscrib(uuid, text, boolean, boolean) to authenticated;

-- ---------- neoscrib_auto, version complète ----------
create or replace function public.neoscrib_auto(p_commune_id bigint, p_year integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start timestamptz;
  v_end timestamptz;
  v_ref timestamptz;
  v jsonb := '{}'::jsonb;
  r record;
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction';
  end if;

  select make_timestamptz(p_year, 1, 1, 0, 0, 0, coalesce(c.timezone, 'UTC')),
         make_timestamptz(p_year + 1, 1, 1, 0, 0, 0, coalesce(c.timezone, 'UTC'))
    into v_start, v_end
    from public.communes c where c.id = p_commune_id;
  v_ref := least(v_end, now());

  -- Exemplaires présents dans la médiathèque : les siens, plus les dépôts de
  -- la BD. Famille (livre, périodique, livre audio, musique, vidéo, jeu,
  -- autre) et public (jeunesse si catégorie Jeunesse : la FAQ de l'enquête
  -- range les ados en jeunesse).
  create temporary table if not exists _neo_ex (
    copy_id bigint, famille text, jeunesse boolean, source text,
    created_at timestamptz, withdrawn_at timestamptz
  ) on commit drop;
  truncate _neo_ex;
  insert into _neo_ex
  select bc.id,
         case
           when b.format ilike 'jeu%soci%' then 'jeu'
           when b.format ilike 'jeu%vid%' then 'jeu_video'
           when dt.kind = 'livre_audio' then 'livre_audio'
           when dt.kind = 'cd' then 'musique'
           when dt.kind = 'dvd' then 'video'
           when dt.kind = 'periodique' then 'periodique'
           when dt.kind = 'autre' then 'autre'
           else 'livre'
         end,
         coalesce(b.category = 'Jeunesse', false),
         coalesce(bc.source, 'purchase'),
         bc.created_at,
         coalesce(bc.withdrawn_at, case when bc.status = 'withdrawn' then bc.created_at end)
    from public.book_copies bc
    join public.books b on b.id = bc.book_id
    left join lateral (
      select d.kind from public.document_types d
       where lower(d.label) = lower(b.format)
         and (d.commune_id is null or d.commune_id = p_commune_id)
       order by d.commune_id nulls last limit 1
    ) dt on true
   where bc.owner_commune_id = p_commune_id;

  -- Fonds propre (hors dépôt BD) au 31/12, acquisitions, éliminations.
  for r in
    select famille, jeunesse,
      count(*) filter (where source <> 'depot_bd' and created_at < v_ref and (withdrawn_at is null or withdrawn_at >= v_ref)) as fonds,
      count(*) filter (where source <> 'depot_bd' and created_at >= v_start and created_at < v_end) as acq,
      count(*) filter (where source <> 'depot_bd' and withdrawn_at >= v_start and withdrawn_at < v_end) as elim,
      count(*) filter (where source = 'depot_bd' and created_at < v_ref and (withdrawn_at is null or withdrawn_at >= v_ref)) as depot
    from _neo_ex group by 1, 2
  loop
    v := v || jsonb_build_object('_f_' || r.famille || '_' || case when r.jeunesse then 'j' else 'a' end,
                                 jsonb_build_array(r.fonds, r.acq, r.elim, r.depot));
  end loop;
  v := v || jsonb_build_object('D131', (select count(*) from _neo_ex
           where source = 'donation' and famille = 'livre' and created_at >= v_start and created_at < v_end));

  -- Emprunteurs connus : comptes de l'appli et adhérents servis au comptoir.
  create temporary table if not exists _neo_pers (
    k text primary key, age text, resident boolean, collectivite boolean,
    inscrit boolean, nouveau boolean
  ) on commit drop;
  truncate _neo_pers;
  insert into _neo_pers
  select p.id::text, p.age_group, p.resident, coalesce(p.is_collectivite, false),
         (p.commune_confirmed = true and coalesce(p.role, 'usager') = 'usager' and p.created_at < v_ref
            and (p.membership_expires_at is null or p.membership_expires_at >= v_start)),
         (p.commune_confirmed = true and coalesce(p.role, 'usager') = 'usager'
            and p.created_at >= v_start and p.created_at < v_end)
    from public.profiles p where p.commune_id = p_commune_id;
  insert into _neo_pers
  select 'adh' || a.id::text,
         case when a.date_naissance is null then null
              when age(make_date(p_year, 12, 31), a.date_naissance) < interval '15 years' then 'enfant'
              when age(make_date(p_year, 12, 31), a.date_naissance) < interval '65 years' then 'adulte'
              else 'senior' end,
         null, false,
         (a.rattache_a is null and a.importe_le < v_ref and (a.adhesion_jusqu_au is null or a.adhesion_jusqu_au >= v_start)),
         false
    from public.adherents_importes a where a.commune_id = p_commune_id
  on conflict do nothing;

  -- Prêts de l'année.
  create temporary table if not exists _neo_pr (
    famille text, jeunesse boolean, depot boolean, emprunteur text
  ) on commit drop;
  truncate _neo_pr;
  insert into _neo_pr
  select e.famille, e.jeunesse, e.source = 'depot_bd',
         coalesce(l.user_id::text, 'adh' || l.adherent_importe_id::text, 'anon' || l.id::text)
    from public.loans l
    join _neo_ex e on e.copy_id = l.copy_id
   where l.borrowed_at_commune_id = p_commune_id
     and l.borrowed_at >= v_start and l.borrowed_at < v_end;
  -- Exemplaires d'une autre médiathèque prêtés ici (réseau, transferts).
  insert into _neo_pr
  select case when b.format ilike 'jeu%soci%' then 'jeu' when b.format ilike 'jeu%vid%' then 'jeu_video' else 'livre' end,
         coalesce(b.category = 'Jeunesse', false), false,
         coalesce(l.user_id::text, 'adh' || l.adherent_importe_id::text, 'anon' || l.id::text)
    from public.loans l
    join public.book_copies bc on bc.id = l.copy_id
    join public.books b on b.id = bc.book_id
   where l.borrowed_at_commune_id = p_commune_id
     and bc.owner_commune_id <> p_commune_id
     and l.borrowed_at >= v_start and l.borrowed_at < v_end;

  -- Les collectivités sont comptées à part (E143, E144, E240).
  for r in
    select pr.famille, pr.jeunesse, count(*) as n, count(*) filter (where pr.depot) as nd
      from _neo_pr pr left join _neo_pers ps on ps.k = pr.emprunteur
     group by 1, 2
  loop
    v := v || jsonb_build_object('_p_' || r.famille || '_' || case when r.jeunesse then 'j' else 'a' end, r.n,
                                 '_pd_' || r.famille || '_' || case when r.jeunesse then 'j' else 'a' end, r.nd);
  end loop;

  -- Usagers (particuliers) : inscrits actifs, nouveaux, emprunteurs actifs,
  -- par tranche d'âge et résidence. Un emprunteur de l'année est forcément
  -- un inscrit actif.
  create temporary table if not exists _neo_u (
    k text, age text, resident boolean, inscrit boolean, nouveau boolean, emprunteur boolean
  ) on commit drop;
  truncate _neo_u;
  insert into _neo_u
  select x.k, ps.age, ps.resident,
         coalesce(ps.inscrit, false) or x.emp, coalesce(ps.nouveau, false), x.emp
    from (
      select k, bool_or(emp) as emp from (
        select k, false as emp from _neo_pers where inscrit or nouveau
        union all
        select emprunteur, true from _neo_pr where emprunteur not like 'anon%'
      ) t group by k
    ) x
    left join _neo_pers ps on ps.k = x.k
   where not coalesce(ps.collectivite, false);

  v := v || jsonb_build_object(
    'C201', 'Oui',
    'C202', (select count(*) from public.books b
              where b.commune_id = p_commune_id and coalesce(b.archived, false) = false
                and b.created_at < v_ref
                and exists (select 1 from public.book_copies bc where bc.book_id = b.id
                              and bc.owner_commune_id = p_commune_id and coalesce(bc.source, 'purchase') <> 'depot_bd')),
    'C206', 'BliGO',
    'E110', (select count(*) from _neo_u where inscrit and age = 'enfant'),
    'E111', (select count(*) from _neo_u where nouveau and age = 'enfant'),
    'E112', (select count(*) from _neo_u where emprunteur and age = 'enfant'),
    'E119', (select count(*) from _neo_u where inscrit and age = 'adulte'),
    'E120', (select count(*) from _neo_u where nouveau and age = 'adulte'),
    'E121', (select count(*) from _neo_u where emprunteur and age = 'adulte'),
    'E128', (select count(*) from _neo_u where inscrit and age = 'senior'),
    'E129', (select count(*) from _neo_u where nouveau and age = 'senior'),
    'E130', (select count(*) from _neo_u where emprunteur and age = 'senior'),
    'E137', (select count(*) from _neo_u where inscrit and age in ('adulte', 'senior')),
    'E138', (select count(*) from _neo_u where nouveau and age in ('adulte', 'senior')),
    'E139', (select count(*) from _neo_u where emprunteur and age in ('adulte', 'senior')),
    'E101', (select count(*) from _neo_u where inscrit),
    'E102', (select count(*) from _neo_u where nouveau),
    'E103', (select count(*) from _neo_u where emprunteur),
    'E140', (select count(*) from _neo_u where inscrit and resident),
    'E141', (select count(*) from _neo_u where nouveau and resident),
    'E142', (select count(*) from _neo_u where emprunteur and resident),
    '_sans_age', (select count(*) from _neo_u where emprunteur and age is null),
    '_sans_resid', (select count(*) from _neo_u where emprunteur and resident is null),
    'E143', (select count(*) from _neo_pers where collectivite and inscrit),
    'E144', (select count(distinct pr.emprunteur) from _neo_pr pr join _neo_pers ps on ps.k = pr.emprunteur where ps.collectivite),
    'E240', (select count(*) from _neo_pr pr join _neo_pers ps on ps.k = pr.emprunteur where ps.collectivite),
    'E103_anonymes', (select count(*) from _neo_pr where emprunteur like 'anon%'),
    'E147', (select coalesce(sum(ve.count), 0) from public.visitor_entries ve
              where ve.commune_id = p_commune_id and ve.occurred_at >= v_start and ve.occurred_at < v_end),
    'E302', (select count(*) from public.reservations rs
              join public.profiles p on p.id = rs.user_id
              where p.commune_id = p_commune_id and rs.status <> 'panier'
                and rs.created_at >= v_start and rs.created_at < v_end),
    'E504', 'Oui',
    '_abos_a', (select count(*) from public.books b
                 where b.commune_id = p_commune_id and coalesce(b.archived, false) = false
                   and coalesce(b.category, '') <> 'Jeunesse'
                   and exists (select 1 from public.document_types dt where dt.kind = 'periodique'
                                 and lower(dt.label) = lower(b.format)
                                 and (dt.commune_id is null or dt.commune_id = p_commune_id))),
    '_abos_j', (select count(*) from public.books b
                 where b.commune_id = p_commune_id and coalesce(b.archived, false) = false
                   and b.category = 'Jeunesse'
                   and exists (select 1 from public.document_types dt where dt.kind = 'periodique'
                                 and lower(dt.label) = lower(b.format)
                                 and (dt.commune_id is null or dt.commune_id = p_commune_id)))
  );

  -- Actions culturelles de l'agenda : par type et par public.
  -- Population touchée = participants saisis, sinon présents pointés, sinon inscrits.
  for r in
    select coalesce(ev.event_type, 'Autre') as t, coalesce(ev.audience, 'tous') as aud,
           count(*) as n,
           sum(coalesce(ev.participants, greatest(
             (select count(*) from public.event_checkins ck where ck.event_id = ev.id),
             (select count(*) from public.event_rsvps rv where rv.event_id = ev.id)))) as pop
      from public.events ev
     where ev.commune_id = p_commune_id
       and ev.event_date >= v_start and ev.event_date < v_end
     group by 1, 2
  loop
    v := v || jsonb_build_object('_h_' || r.t || '_' || r.aud, jsonb_build_array(r.n, r.pop));
  end loop;

  return v;
end;
$$;

grant execute on function public.neoscrib_auto(bigint, integer) to authenticated;
