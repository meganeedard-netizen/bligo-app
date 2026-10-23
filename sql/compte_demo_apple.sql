-- Compte démo pour la vérification Apple (23/10/2026)
-- Le compte demo-apple@bligo.fr a été créé par l'inscription normale de
-- l'appli (rattaché à Val-Fleuri). Ce script le rend utilisable tout de suite :
-- e-mail confirmé (pas de boîte mail réelle derrière), inscription validée,
-- catégorie Majeur, adhésion valable jusqu'à fin 2027.
-- Le mot de passe n'est pas ici : il est dans visuels-stores/compte-demo-apple.txt.

update auth.users
set email_confirmed_at = coalesce(email_confirmed_at, now())
where email = 'demo-apple@bligo.fr';

update public.profiles
set commune_id = 1,
    full_name = 'Démo Apple',
    tariff_category = 'majeur',
    registration_status = 'valide',
    validated_at = now(),
    membership_expires_at = '2027-12-31 23:59:59+00'
where id = (select id from auth.users where email = 'demo-apple@bligo.fr');

-- Vérification : doit afficher une ligne « valide », Val-Fleuri, e-mail confirmé.
select u.email, u.email_confirmed_at is not null as email_confirme,
       p.full_name, p.registration_status, p.tariff_category, p.commune_id, p.membership_expires_at
from auth.users u join public.profiles p on p.id = u.id
where u.email = 'demo-apple@bligo.fr';
