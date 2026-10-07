-- Diagnostic « Prêts en cours vides » dans le back-office (07/10/2026)
-- LECTURE SEULE : ne modifie rien. À coller dans Supabase > SQL Editor > Run,
-- puis copier le tableau de résultat à Claude.

select 'A. Prêts en cours (table loans, non rendus)' as controle,
       count(*)::text as valeur
from public.loans where returned_at is null
union all
select 'B. Réservations "récupérées" SANS prêt associé',
       count(*)::text
from public.reservations r
where r.status = 'recupere'
  and not exists (select 1 from public.loans l where l.reservation_id = r.id)
union all
select 'C. Fonction mark_reservation_picked_up installée ?',
       case when exists (select 1 from pg_proc where proname = 'mark_reservation_picked_up') then 'oui' else 'NON' end
union all
select 'D. Prêts en cours par médiathèque (id commune : nombre)',
       coalesce(string_agg(x.commune_id::text || ' : ' || x.n, ' | '), 'aucun')
from (select borrowed_at_commune_id as commune_id, count(*) as n
      from public.loans where returned_at is null group by 1) x
union all
select 'E. Comptes agents/admin (nom, rôle, commune)',
       coalesce(string_agg(coalesce(p.full_name, '?') || ' / ' || p.role || ' / ' || coalesce(p.commune_id::text, 'aucune'), ' | '), 'aucun')
from public.profiles p where p.role in ('agent', 'super_admin');
