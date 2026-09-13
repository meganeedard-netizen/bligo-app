-- Répare les prêts hors condition pris AVANT la création de la table
-- free_book_loans (ex : « Le Petit Prince ») : le livre est bien marqué comme
-- pris dans free_books, mais aucune fiche de suivi n'existe, donc il
-- n'apparaît nulle part dans "Mes réservations". On crée la fiche manquante
-- en statut "En préparation" — un agent pourra la faire avancer normalement
-- depuis l'écran "Livres hors condition" du back-office.

insert into public.free_book_loans (free_book_id, user_id, status)
select fb.id, fb.borrowed_by, 'preparation'
from public.free_books fb
where fb.borrowed_by is not null
  and not exists (
    select 1 from public.free_book_loans l
    where l.free_book_id = fb.id
      and l.user_id = fb.borrowed_by
      and l.status in ('preparation', 'pret')
  );
