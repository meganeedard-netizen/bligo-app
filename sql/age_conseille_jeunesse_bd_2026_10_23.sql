-- BliGO : âge conseillé des livres jeunesse et BD de Val-Fleuri (23/10/2026),
-- repris de la notice BnF (zone 333, avis du Centre national de la
-- littérature pour la jeunesse). Seulement quand la BnF l'indique.
update public.books b set age_range = v.age
from (values
  ('9782075139106', 'Dès 11 ans'),  -- Alma, tome 1
  ('9782075090254', 'Dès 11 ans'),  -- Jefferson
  ('9782075083805', 'Dès 3 ans'),   -- Le renard et l'étoile
  ('9782266270663', 'Dès 11 ans'),  -- Gardiens des cités perdues, tome 1
  ('9782016285985', 'Dès 11 ans'),  -- Skandar et le vol de la licorne
  ('9782205211627', 'Dès 13 ans'),  -- La jungle
  ('9782370730145', 'Dès 15 ans'),  -- L'Arabe du futur, tome 1
  ('9782205088168', 'Dès 15 ans'),  -- Le monde sans fin
  ('9782380710243', 'Dès 11 ans'),  -- Spy x Family, tome 1
  ('9782205076394', 'Dès 11 ans'),  -- Dans la combi de Thomas Pesquet
  ('9782344010648', 'Dès 15 ans')   -- Peau d'homme
) as v(isbn, age)
where b.commune_id = 1 and b.isbn = v.isbn and b.age_range is null;

-- Vérification
select title, age_range from public.books
where commune_id = 1 and category in ('Jeunesse', 'BD') order by category, title;
