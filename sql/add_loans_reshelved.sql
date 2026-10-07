-- « À remettre en rayon » déplacé dans l'onglet Retours (07/10/2026)
-- ============================================================
-- Jusqu'ici, la checklist « À remettre en rayon » ne lisait que les
-- réservations expirées : un livre rendu après un emprunt au comptoir (sans
-- réservation) n'y apparaissait jamais. On suit maintenant la remise en rayon
-- directement sur le prêt.
--
-- reshelved = true par défaut : les prêts déjà rendus avant cette migration ne
-- remontent pas dans la liste. Un trigger le repasse à false au moment du
-- retour (scan_return ou « Marquer rendu »), sans toucher à scan_return.

alter table public.loans add column if not exists reshelved boolean not null default true;

create or replace function public.loans_mark_to_reshelve()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.returned_at is null and new.returned_at is not null then
    new.reshelved := false;
    -- Le livre est désormais suivi par son prêt : la réservation d'origine ne
    -- doit pas apparaître une deuxième fois comme « non récupérée ».
    if new.reservation_id is not null then
      update public.reservations set reshelved = true where id = new.reservation_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_loans_mark_to_reshelve on public.loans;
create trigger trg_loans_mark_to_reshelve
  before update on public.loans
  for each row execute function public.loans_mark_to_reshelve();
