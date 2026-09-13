-- Retire "Contes et légendes de Guadeloupe" de la Bibliothèque Libre (Le Moule).
delete from public.free_books
where title = 'Contes et légendes de Guadeloupe';
