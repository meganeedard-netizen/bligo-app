-- BliGO — Coup de cœur de la médiathèque (16/09/2026)
-- Chaque médiathèque met en avant jusqu'à 8 livres de son choix. Géré depuis
-- admin.html (Catalogue : badge, fiche livre, sélection multiple), visible
-- côté usager dans accueil.html via un onglet dédié du catalogue.
--
-- À exécuter APRÈS sql/fix_books_missing_commune_id_2026_09_16.sql (le
-- plafond est compté par commune_id, les livres doivent déjà être rattachés
-- à leur médiathèque).
--
-- Migration ADDITIVE : ne modifie ni ne supprime aucune table existante.
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

alter table public.books add column if not exists is_staff_pick boolean not null default false;

-- Vérifie le plafond de 8 côté base, quel que soit le chemin utilisé pour
-- passer un livre en coup de cœur (fiche par fiche ou sélection multiple
-- dans admin.html) : la vérification côté client est un confort d'UI, pas
-- une vraie garantie si deux agents modifient en même temps.
create or replace function public.enforce_staff_pick_cap()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if new.is_staff_pick and not coalesce(old.is_staff_pick, false) then
    select count(*) into v_count
    from public.books
    where is_staff_pick = true
      and commune_id is not distinct from new.commune_id
      and id <> new.id;

    if v_count >= 8 then
      raise exception 'Cette médiathèque a déjà 8 coups de cœur (le maximum). Retire-en un avant d''en ajouter un nouveau.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_staff_pick_cap on public.books;
create trigger trg_enforce_staff_pick_cap
  before insert or update of is_staff_pick on public.books
  for each row execute function public.enforce_staff_pick_cap();

-- Sélection de départ (8 livres, choisis à la main pour varier les genres :
-- fonds local, roman, thriller, jeunesse, développement personnel, société),
-- pour ne pas démarrer avec un onglet vide côté usager. Mégane ajuste ensuite
-- depuis Catalogue > fiche livre ou la sélection multiple.
update public.books set is_staff_pick = true
where id in (1, 15, 28, 29, 31, 33, 48, 61) and equipped = true;
