-- Agenda (26/11/2026, RDV Brest : ~300 événements par an) : tranche d'âge
-- précise et âge minimum, pour filtrer dans l'appli. La colonne audience
-- (tous / enfants) reste celle des rapports Néoscrib et du bilan : elle est
-- déduite de la tranche d'âge par le logiciel.
alter table public.events add column if not exists age_group text;
alter table public.events add column if not exists min_age integer;
alter table public.events add column if not exists max_age integer;
do $$ begin
  alter table public.events add constraint events_age_group_check
    check (age_group is null or age_group in ('tous', 'familles', 'tout_petits', 'enfants', 'ados', 'adultes'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.events add constraint events_ages_check
    check ((min_age is null or min_age between 0 and 99) and (max_age is null or max_age between 0 and 99) and (min_age is null or max_age is null or max_age >= min_age));
exception when duplicate_object then null; end $$;
update public.events set age_group = coalesce(audience, 'tous') where age_group is null;
