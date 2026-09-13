-- Ajoute les vraies couvertures aux 8 derniers livres qui n'en avaient pas encore
-- (le socle littérature antillaise / classiques du catalogue).

update public.books set cover_url = 'img/covers/texaco.jpg' where id = 1;
update public.books set cover_url = 'img/covers/pluie-et-vent-sur-telumee-miracle.jpg' where id = 2;
update public.books set cover_url = 'img/covers/une-si-longue-lettre.jpg' where id = 3;
update public.books set cover_url = 'img/covers/cahier-dun-retour-au-pays-natal.jpg' where id = 4;
update public.books set cover_url = 'img/covers/ti-jean-lhorizon.jpg' where id = 5;
update public.books set cover_url = 'img/covers/les-soleils-des-independances.jpg' where id = 6;
update public.books set cover_url = 'img/covers/letranger.jpg' where id = 7;
update public.books set cover_url = 'img/covers/la-saison-de-lombre.jpg' where id = 8;
