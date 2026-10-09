-- Règles de cote réglables par médiathèque (09/10/2026)
-- ============================================================
-- Chaque médiathèque a sa façon de coter (« P R MUSS » pour un roman
-- policier de Musso, « R MUS », « 843 MUS »…). communes.cote_rules garde
-- ses règles ; null = règles BliGO par défaut (voir DEFAULT_COTE_RULES dans
-- admin.html). Format :
--   { "author_letters": 3, "dewey_decimals": 1,
--     "categories": { "Thriller": { "prefix": "P R", "mode": "lettres" }, ... },
--     "usuel_prefix": "U", "cd_prefix": "CD", "dvd_prefix": "DVD" }
-- mode : « lettres » (préfixe + auteur), « dewey » (préfixe + indice + auteur),
-- « auto » (indice si c'est un documentaire, sinon lettres).

alter table public.communes add column if not exists cote_rules jsonb;

create or replace function public.update_commune_cote_rules(p_commune_id bigint, p_rules jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or (public.is_direction() and public.agent_commune_id() = p_commune_id)) then
    raise exception 'Réservé à la direction de cette médiathèque';
  end if;
  update public.communes set cote_rules = p_rules where id = p_commune_id;
end;
$$;

grant execute on function public.update_commune_cote_rules(bigint, jsonb) to authenticated;

-- ============================================================
-- Accessibilité (09/10/2026) : 3 types de documents demandés aux médiathèques
-- ============================================================
insert into public.document_types (commune_id, label, kind, sort_order) values
  (null, 'Gros caractères', 'livre', 35),
  (null, 'Livre adapté DYS', 'livre', 36),
  (null, 'FALC (facile à lire et à comprendre)', 'livre', 37)
on conflict do nothing;
