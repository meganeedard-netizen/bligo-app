 -- BliGO : rapport annuel Néoscrib 2026 (13/11/2026)
-- ============================================================
-- Suite à l'échange avec la Bibliothèque départementale de Guadeloupe
-- (R. Mallégol) et aux formulaires 2026 de l'Observatoire de la lecture
-- publique (rapport très abrégé et rapport basique, mis en ligne par la BD de
-- la Haute-Vienne).
--
-- 1. neoscrib_auto(commune, année) : tous les indicateurs que BliGO peut
--    calculer seul, rangés sous leur VRAI code Néoscrib 2026 (D101, E203...).
--    Les fonds sont comptés en exemplaires (unités matérielles, « UM »),
--    comme le demande l'enquête, et non en notices.
--    Fonds = état au 31/12 de l'année (ou aujourd'hui pour l'année en cours).
-- 2. neoscrib_saisies : ce que la médiathèque saisit à la main (surface,
--    personnel, budget, partenariats...), gardé d'une année sur l'autre.
--
-- sigb_annual_stats (ancienne version) n'est pas supprimée.
-- À exécuter dans Supabase : SQL Editor > New query > Run.

-- ---------- 1. Saisies manuelles ----------
create table if not exists public.neoscrib_saisies (
  commune_id bigint not null references public.communes(id) on delete cascade,
  annee integer not null,
  code text not null,
  valeur text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  primary key (commune_id, annee, code)
);

alter table public.neoscrib_saisies enable row level security;

drop policy if exists "La direction lit les saisies Neoscrib de sa médiathèque" on public.neoscrib_saisies;
create policy "La direction lit les saisies Neoscrib de sa médiathèque"
  on public.neoscrib_saisies for select
  using (public.is_super_admin() or (public.is_direction() and commune_id = public.agent_commune_id()));

drop policy if exists "La direction saisit les données Neoscrib de sa médiathèque" on public.neoscrib_saisies;
create policy "La direction saisit les données Neoscrib de sa médiathèque"
  on public.neoscrib_saisies for all
  using (public.is_super_admin() or (public.is_direction() and commune_id = public.agent_commune_id()))
  with check (public.is_super_admin() or (public.is_direction() and commune_id = public.agent_commune_id()));

-- ---------- 2. Indicateurs calculés ----------
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

  -- Exemplaires de la médiathèque, classés comme dans l'enquête :
  -- famille (livre, périodique, livre audio, musique, vidéo, jeu, autre)
  -- et public (jeunesse si catégorie Jeunesse, adulte sinon : la FAQ de
  -- l'enquête range les ados en jeunesse).
  create temporary table if not exists _neo_ex (
    copy_id bigint, famille text, jeunesse boolean,
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

  -- Fonds au 31/12, acquisitions et éliminations de l'année, par famille/public.
  for r in
    select famille, jeunesse,
      count(*) filter (where created_at < v_ref and (withdrawn_at is null or withdrawn_at >= v_ref)) as fonds,
      count(*) filter (where created_at >= v_start and created_at < v_end) as acq,
      count(*) filter (where withdrawn_at >= v_start and withdrawn_at < v_end) as elim
    from _neo_ex group by 1, 2
  loop
    v := v || jsonb_build_object('_f_' || r.famille || '_' || case when r.jeunesse then 'j' else 'a' end,
                                 jsonb_build_array(r.fonds, r.acq, r.elim));
  end loop;

  -- Prêts de l'année (comptes de l'appli ET adhérents servis au comptoir).
  create temporary table if not exists _neo_pr (
    famille text, jeunesse boolean, emprunteur text
  ) on commit drop;
  truncate _neo_pr;
  insert into _neo_pr
  select e.famille, e.jeunesse,
         coalesce(l.user_id::text, 'adh' || l.adherent_importe_id::text, 'anon' || l.id::text)
    from public.loans l
    join _neo_ex e on e.copy_id = l.copy_id
   where l.borrowed_at_commune_id = p_commune_id
     and l.borrowed_at >= v_start and l.borrowed_at < v_end;
  -- Prêts d'exemplaires d'une autre médiathèque (transferts, réseau).
  insert into _neo_pr
  select case
           when b.format ilike 'jeu%soci%' then 'jeu'
           when b.format ilike 'jeu%vid%' then 'jeu_video'
           else 'livre' end,
         coalesce(b.category = 'Jeunesse', false),
         coalesce(l.user_id::text, 'adh' || l.adherent_importe_id::text, 'anon' || l.id::text)
    from public.loans l
    join public.book_copies bc on bc.id = l.copy_id
    join public.books b on b.id = bc.book_id
   where l.borrowed_at_commune_id = p_commune_id
     and bc.owner_commune_id <> p_commune_id
     and l.borrowed_at >= v_start and l.borrowed_at < v_end;

  for r in
    select famille, jeunesse, count(*) as n from _neo_pr group by 1, 2
  loop
    v := v || jsonb_build_object('_p_' || r.famille || '_' || case when r.jeunesse then 'j' else 'a' end, r.n);
  end loop;

  v := v || jsonb_build_object(
    -- C2 Catalogue
    'C201', 'Oui',
    'C202', (select count(*) from public.books b
              where b.commune_id = p_commune_id and coalesce(b.archived, false) = false
                and b.created_at < v_ref
                and exists (select 1 from public.book_copies bc where bc.book_id = b.id and bc.owner_commune_id = p_commune_id)),
    'C206', 'BliGO',
    -- E1 Usagers
    -- Inscrits actifs = usagers rattachés et à jour d'adhésion, adhérents
    -- importés pas encore sur l'appli, et toute personne qui a emprunté dans
    -- l'année (un emprunteur actif est forcément un inscrit actif).
    'E101', (select count(*) from (
               select p.id::text as k from public.profiles p
                where p.commune_id = p_commune_id and coalesce(p.role, 'usager') = 'usager'
                  and p.commune_confirmed = true and p.created_at < v_ref
                  and (p.membership_expires_at is null or p.membership_expires_at >= v_start)
               union
               select 'adh' || a.id::text from public.adherents_importes a
                where a.commune_id = p_commune_id and a.rattache_a is null and a.importe_le < v_ref
                  and (a.adhesion_jusqu_au is null or a.adhesion_jusqu_au >= v_start)
               union
               select emprunteur from _neo_pr where emprunteur not like 'anon%'
             ) t),
    'E102', (select count(*) from public.profiles p
              where p.commune_id = p_commune_id and coalesce(p.role, 'usager') = 'usager'
                and p.commune_confirmed = true
                and p.created_at >= v_start and p.created_at < v_end),
    -- Prêts anonymisés (durée de conservation dépassée) : l'emprunteur n'est
    -- plus connu, ils sont signalés à part pour que la médiathèque le sache.
    'E103', (select count(distinct emprunteur) from _neo_pr where emprunteur not like 'anon%'),
    'E103_anonymes', (select count(*) from _neo_pr where emprunteur like 'anon%'),
    'E147', (select coalesce(sum(ve.count), 0) from public.visitor_entries ve
              where ve.commune_id = p_commune_id and ve.occurred_at >= v_start and ve.occurred_at < v_end),
    -- E3 Réservations
    'E302', (select count(*) from public.reservations rs
              join public.profiles p on p.id = rs.user_id
              where p.commune_id = p_commune_id and rs.status <> 'panier'
                and rs.created_at >= v_start and rs.created_at < v_end),
    'E504', 'Oui',
    -- D2 : titres de type Périodique au catalogue = abonnements (à vérifier).
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

  -- H4 Actions culturelles : événements de l'agenda de l'année, par type.
  -- Population touchée = présents pointés, sinon inscrits.
  for r in
    select coalesce(ev.event_type, 'Autre') as t,
           count(*) as n,
           sum(greatest(
             (select count(*) from public.event_checkins ck where ck.event_id = ev.id),
             (select count(*) from public.event_rsvps rv where rv.event_id = ev.id))) as pop
      from public.events ev
     where ev.commune_id = p_commune_id
       and ev.event_date >= v_start and ev.event_date < v_end
     group by 1
  loop
    v := v || jsonb_build_object('_h_' || r.t, jsonb_build_array(r.n, r.pop));
  end loop;

  return v;
end;
$$;

grant execute on function public.neoscrib_auto(bigint, integer) to authenticated;
