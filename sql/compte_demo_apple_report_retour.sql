-- Compte démo Apple : repousse au 30/11/2026 la date de retour de l'emprunt
-- en cours, pour qu'il ne soit jamais en retard pendant la vérification
-- d'Apple (demandé par Mégane le 23/10/2026).
update public.loans l
set due_at = '2026-11-30 18:00:00-04'
where l.user_id = (select id from auth.users where email = 'demo-apple@bligo.fr')
  and l.returned_at is null;

update public.reservations r
set return_due_at = '2026-11-30 18:00:00-04'
where r.user_id = (select id from auth.users where email = 'demo-apple@bligo.fr')
  and r.id in (select reservation_id from public.loans
               where user_id = r.user_id and returned_at is null);

-- Vérification : doit afficher La Porteuse de lettres, retour le 30/11/2026.
select b.title, l.due_at, r.return_due_at
from public.loans l
join public.book_copies c on c.id = l.copy_id
join public.books b on b.id = c.book_id
left join public.reservations r on r.id = l.reservation_id
where l.user_id = (select id from auth.users where email = 'demo-apple@bligo.fr')
  and l.returned_at is null;
