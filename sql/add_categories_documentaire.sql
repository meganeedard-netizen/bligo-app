-- Nouvelles catégories Dewey + type « Livre audio » distinct (07/10/2026)
-- ============================================================
-- 1. Catégories ajoutées à la demande de Mégane, alignées sur les classes
--    Dewey des bibliothèques : Documentaire (catégorie par défaut des
--    documentaires 000-600 non couverts ailleurs), Sciences & nature (500),
--    Voyages (910-919), Sports & loisirs (790-799), Poésie & théâtre (8x1, 8x2).
-- 2. Le type « Livre audio » prend son propre kind ('livre_audio'), pour le
--    filtre par type du catalogue usager (Livres / Livres audio / CD / DVD / Revues).
-- À exécuter APRÈS add_document_types_and_dewey.sql.

alter table public.books drop constraint if exists books_category_check;
alter table public.books add constraint books_category_check check (
  category is null or category in (
    'Fonds local', 'Roman', 'Thriller', 'Fantasy', 'Jeunesse', 'BD',
    'Poésie & théâtre', 'Documentaire', 'Sciences & nature', 'Voyages', 'Sports & loisirs',
    'Bien-être', 'Maison', 'Histoire', 'Culture', 'Autres'
  )
);

alter table public.free_books drop constraint if exists free_books_category_check;
alter table public.free_books add constraint free_books_category_check check (
  category is null or category in (
    'Fonds local', 'Roman', 'Thriller', 'Fantasy', 'Jeunesse', 'BD',
    'Poésie & théâtre', 'Documentaire', 'Sciences & nature', 'Voyages', 'Sports & loisirs',
    'Bien-être', 'Maison', 'Histoire', 'Culture', 'Autres'
  )
);

alter table public.document_types drop constraint if exists document_types_kind_check;
alter table public.document_types add constraint document_types_kind_check
  check (kind in ('livre', 'livre_audio', 'periodique', 'cd', 'dvd', 'autre'));

update public.document_types set kind = 'livre_audio' where commune_id is null and label = 'Livre audio';
