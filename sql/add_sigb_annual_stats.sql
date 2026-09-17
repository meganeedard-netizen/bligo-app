-- BliGO — Évolution vers un SIGB complet, Phase 2 : statistiques SIGB (17/09/2026)
-- Voir BliGo_note_cadrage_SIGB_rapport_annuel.pdf.
--
-- Calcule les indicateurs "Automatique" de la cartographie Neoscrib qui sont
-- déjà déductibles des données réelles de BliGO aujourd'hui (catalogue,
-- collections, usagers, prêts, réservations, fréquentation). Honnêtement
-- limité à ce qui existe vraiment : pas de périodiques, pas de finances, pas
-- de personnel — ce sera l'objet de phases ultérieures.
--
-- À exécuter APRÈS sql/add_activity_log_and_visitor_counter.sql (utilise
-- activity_events pour les éliminations d'exemplaires).
-- À exécuter dans Supabase : Project > SQL Editor > New query > Run.

create or replace function public.sigb_annual_stats(p_commune_id bigint, p_year integer)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_year_start timestamptz := make_timestamptz(p_year, 1, 1, 0, 0, 0, 'UTC');
  v_year_end timestamptz := make_timestamptz(p_year + 1, 1, 1, 0, 0, 0, 'UTC');
  v_result jsonb;
begin
  if not (public.is_direction() or public.is_super_admin()) then
    raise exception 'Réservé à la direction';
  end if;

  select jsonb_build_object(
    'c2_notices_total', (
      select count(*) from public.books where commune_id = p_commune_id and equipped = true
    ),
    'c2_notices_added_year', (
      select count(*) from public.books
      where commune_id = p_commune_id and created_at >= v_year_start and created_at < v_year_end
    ),
    'd1_fonds_adultes', (
      select count(*) from public.books
      where commune_id = p_commune_id and equipped = true and coalesce(category, '') <> 'Jeunesse'
    ),
    'd1_fonds_jeunesse', (
      select count(*) from public.books
      where commune_id = p_commune_id and equipped = true and category = 'Jeunesse'
    ),
    'd1_acquisitions_year', (
      select count(*) from public.books
      where commune_id = p_commune_id and created_at >= v_year_start and created_at < v_year_end
    ),
    'd1_eliminations_year', (
      select count(*) from public.activity_events
      where commune_id = p_commune_id and event_type = 'copy_status_changed'
        and metadata->>'to' = 'withdrawn'
        and occurred_at >= v_year_start and occurred_at < v_year_end
    ),
    'e1_inscrits_actifs', (
      select count(*) from public.profiles
      where commune_id = p_commune_id and commune_confirmed = true
    ),
    'e1_nouveaux_inscrits_year', (
      select count(*) from public.profiles
      where commune_id = p_commune_id and created_at >= v_year_start and created_at < v_year_end
    ),
    'e1_emprunteurs_actifs_year', (
      select count(distinct l.user_id) from public.loans l
      where l.borrowed_at_commune_id = p_commune_id
        and l.borrowed_at >= v_year_start and l.borrowed_at < v_year_end
    ),
    'e2_prets_total_year', (
      select count(*) from public.loans l
      where l.borrowed_at_commune_id = p_commune_id
        and l.borrowed_at >= v_year_start and l.borrowed_at < v_year_end
    ),
    'e2_prets_jeunesse_year', (
      select count(*) from public.loans l
      join public.book_copies c on c.id = l.copy_id
      join public.books b on b.id = c.book_id
      where l.borrowed_at_commune_id = p_commune_id and b.category = 'Jeunesse'
        and l.borrowed_at >= v_year_start and l.borrowed_at < v_year_end
    ),
    'e2_prets_adultes_year', (
      select count(*) from public.loans l
      join public.book_copies c on c.id = l.copy_id
      join public.books b on b.id = c.book_id
      where l.borrowed_at_commune_id = p_commune_id and coalesce(b.category, '') <> 'Jeunesse'
        and l.borrowed_at >= v_year_start and l.borrowed_at < v_year_end
    ),
    'e3_reservations_year', (
      select count(*) from public.reservations r
      join public.profiles p on p.id = r.user_id
      where p.commune_id = p_commune_id
        and r.created_at >= v_year_start and r.created_at < v_year_end
    ),
    'frequentation_year', (
      select coalesce(sum(count), 0) from public.visitor_entries
      where commune_id = p_commune_id
        and occurred_at >= v_year_start and occurred_at < v_year_end
    )
  ) into v_result;

  return v_result;
end;
$$;
