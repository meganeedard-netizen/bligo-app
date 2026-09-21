-- Corrige la colonne opening_hours, restée en type "text" (21/09/2026)
-- ============================================================
-- add_opening_hours.sql (17/09/2026) faisait :
--   alter table public.communes add column if not exists opening_hours jsonb;
-- Mais la colonne existait déjà en "text" depuis schema.sql (horaires en une
-- seule phrase libre, ancien format) — "ADD COLUMN IF NOT EXISTS" ne change
-- jamais le type d'une colonne existante, donc la conversion en jsonb n'a
-- jamais eu lieu. Résultat : chaque enregistrement des horaires par jour
-- depuis le back-office agent (Tarifs médiathèque) stockait un objet JSON
-- converti en texte brut dans une colonne text, et à la lecture (accueil.html,
-- myOpeningHours?.[jour]) ce texte brut n'est pas indexable par jour — tous
-- les jours affichaient "Fermé", quoi qu'on ait saisi.

-- 1) Retire d'abord la contrainte "not null" et la valeur par défaut :
--    impossible de mettre certaines valeurs à vide (étape 2) tant qu'elle
--    est encore active.
alter table public.communes
  alter column opening_hours drop default,
  alter column opening_hours drop not null;

-- 2) Les horaires en texte libre (ancien format à une seule phrase, ex.
--    "Mardi-Samedi 9h-17h30 · Fermé dimanche et lundi") ne sont pas du JSON
--    valide : remis à vide pour être ressaisis jour par jour depuis le
--    back-office agent (Tarifs médiathèque). Les horaires déjà saisis par
--    jour (ex. Val-Fleuri) sont eux du JSON valide et seront récupérés tels
--    quels par la conversion ci-dessous.
update public.communes
set opening_hours = null
where opening_hours is not null
  and opening_hours !~ '^\s*\{.*\}\s*$';

-- 3) Convertit enfin la colonne en jsonb.
alter table public.communes
  alter column opening_hours type jsonb using opening_hours::jsonb;

comment on column public.communes.opening_hours is 'Horaires d''ouverture, texte libre par jour : {"lundi": "...", "mardi": "...", ..., "dimanche": "..."}. Modifiable uniquement depuis le back-office agent (Tarifs médiathèque, direction).';
