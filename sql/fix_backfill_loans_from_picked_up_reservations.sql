-- Recrée les prêts manquants des réservations « récupérées » (07/10/2026)
-- ============================================================
-- Diagnostic du 07/10/2026 : 0 prêt dans loans, 20 réservations en statut
-- 'recupere' sans prêt associé. Ce sont des retraits validés avant
-- fix_reservation_pickup_creates_loan.sql (22/09/2026) ou posés par les
-- scripts de test : l'usager les voit « Emprunté » / « En retard », mais
-- l'onglet « Prêts en cours » du back-office (qui lit loans) reste vide.
--
-- Ne traite que les réservations que l'usager voit réellement comme en cours
-- (status 'recupere' ET return_due_at renseigné, même règle que
-- reservations.html). Celles sans date de retour sont dans son historique.
--
-- Pour chaque réservation : on prend un exemplaire libre du livre (sans prêt
-- actif), de préférence dans la commune du livre ; s'il n'y en a aucun, on
-- crée un exemplaire avec un code-barres provisoire BLIGO-<livre>-R<résa>,
-- à remplacer par le vrai code au rééquipement (comme la reprise du 13/09).
-- La date de retour reprend return_due_at, pour que « En retard » soit le
-- même chez l'usager et dans le back-office.
--
-- Rejouable sans risque : une réservation qui a déjà un prêt est ignorée.

do $$
declare
  r record;
  v_copy_id bigint;
  v_commune bigint;
  v_created int := 0;
  v_new_copies int := 0;
begin
  for r in
    select res.id, res.user_id, res.book_id, res.created_at, res.return_due_at,
           coalesce(b.commune_id, (select id from public.communes order by id limit 1)) as book_commune
    from public.reservations res
    join public.books b on b.id = res.book_id
    where res.status = 'recupere'
      and res.return_due_at is not null
      and not exists (select 1 from public.loans l where l.reservation_id = res.id)
    order by res.id
  loop
    v_copy_id := null;

    select c.id, c.current_commune_id into v_copy_id, v_commune
    from public.book_copies c
    where c.book_id = r.book_id
      and c.status not in ('lost', 'withdrawn', 'in_transit')
      and not exists (select 1 from public.loans l where l.copy_id = c.id and l.returned_at is null)
    order by (c.current_commune_id = r.book_commune) desc, (c.status = 'available') desc, c.id
    limit 1;

    if v_copy_id is null then
      insert into public.book_copies (book_id, barcode, owner_commune_id, current_commune_id, status)
      values (r.book_id, 'BLIGO-' || lpad(r.book_id::text, 6, '0') || '-R' || r.id,
              r.book_commune, r.book_commune, 'borrowed')
      returning id, current_commune_id into v_copy_id, v_commune;
      v_new_copies := v_new_copies + 1;
    end if;

    insert into public.loans (copy_id, user_id, reservation_id, borrowed_at_commune_id, borrowed_at, due_at)
    values (v_copy_id, r.user_id, r.id, v_commune, r.created_at, r.return_due_at);

    update public.book_copies set status = 'borrowed' where id = v_copy_id;
    v_created := v_created + 1;
  end loop;

  raise notice 'Prêts recréés : %, exemplaires créés : %', v_created, v_new_copies;
end $$;

-- Vérification : à quoi ressemble « Prêts en cours » maintenant.
select 'Prêts en cours (total)' as controle, count(*)::text as valeur
from public.loans where returned_at is null
union all
select 'Prêts en cours par médiathèque (id commune : nombre)',
       coalesce(string_agg(x.c::text || ' : ' || x.n, ' | '), 'aucun')
from (select borrowed_at_commune_id as c, count(*) as n
      from public.loans where returned_at is null group by 1) x
union all
select 'Réservations récupérées encore sans prêt (sans date de retour, normal)',
       count(*)::text
from public.reservations r
where r.status = 'recupere'
  and not exists (select 1 from public.loans l where l.reservation_id = r.id);
