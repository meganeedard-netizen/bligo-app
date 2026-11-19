-- Carte des médiathèques du réseau (19/11/2026) : coordonnées des communes.
alter table public.communes add column if not exists lat double precision;
alter table public.communes add column if not exists lng double precision;
-- Réseau de démo placé en Guadeloupe (démo BDP Guadeloupe, modifiable).
update public.communes set lat = 16.2490, lng = -61.5940 where id = 8;  -- BDP (démo)
update public.communes set lat = 16.3140, lng = -61.3440 where id = 9;  -- Beaumont
update public.communes set lat = 16.3320, lng = -61.6970 where id = 10; -- Clairval
update public.communes set lat = 16.0510, lng = -61.5640 where id = 11; -- Montfort
