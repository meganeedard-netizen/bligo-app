-- BliGO — Sélection BliGO de septembre 2026 (14/09/2026)
-- Top 20 des livres les plus vendus au 1er semestre 2026, saisi par Mégane.
-- Couvertures et ISBN récupérés automatiquement via Google Books (Open Library en appoint).
-- Prérequis : sql/add_stats_and_monthly_top20.sql
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

insert into public.monthly_top_books (month, rank, title, author, isbn, cover_url) values
  ('2026-09-01', 1, 'La Prof', 'Freida McFadden', null, 'https://books.google.com/books/content?id=q0HvEQAAQBAJ&printsec=frontcover&img=1&zoom=1&edge=curl&source=gbs_api'),
  ('2026-09-01', 2, 'Les Belles Promesses', 'Pierre Lemaitre', '9782702191965', 'https://books.google.com/books/content?id=ysWaEQAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 3, 'La femme de ménage', 'Freida McFadden', '9782290391174', 'https://books.google.com/books/content?id=dNYp0AEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 4, 'Je suis Romane Monnier', 'Delphine de Vigan', '9782379324284', 'https://books.google.com/books/content?id=bJAA0gEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 5, 'D''autres printemps', 'Virginie Grimaldi', '9782898263484', 'https://books.google.com/books/content?id=PEvWEQAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 6, 'Le crime du paradis', 'Guillaume Musso', '9782702192979', 'https://books.google.com/books/content?id=gALh0QEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 7, 'La psy', 'Freida McFadden', '9782824638874', 'https://books.google.com/books/content?id=f6yw0AEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 8, 'BD Mortelle Adèle - Tome 23 - Nazebrocadabra !', 'Mr Tan & Diane Le Feyer', '9782494678767', 'https://books.google.com/books/content?id=aEjTEQAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 9, 'L''autre moi', 'Franck Thilliez', '9782265159075', 'https://books.google.com/books/content?id=mVkB0gEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 10, 'Fauves', 'Mélissa Da Costa', '9782226508812', 'https://books.google.com/books/content?id=rFqlEQAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 11, 'La femme de ménage voit tout', 'Freida McFadden', '9782824627571', 'https://books.google.com/books/content?id=O8Tm0AEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 12, 'Que la mort nous frôle', 'Michel Bussi', '9782258214477', 'https://books.google.com/books/content?id=JesO0gEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 13, 'Le visage de la nuit', 'Cécile Coulon', '9782898763434', 'https://books.google.com/books/content?id=T33REQAAQBAJ&printsec=frontcover&img=1&zoom=1&edge=curl&source=gbs_api'),
  ('2026-09-01', 14, 'Les Carnets de l''apothicaire - Tome 16', 'Natsu Hyuuga & Kurage Neko', '9791032723029', 'https://books.google.com/books/content?id=88W9EQAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 15, 'Ne jamais trembler', 'Stephen King', '9782226509253', 'https://books.google.com/books/content?id=4NG2EQAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 16, 'Les secrets de la femme de ménage', 'Freida McFadden', '9782824638416', 'https://books.google.com/books/content?id=GnjYEAAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 17, 'La Légende', 'Boualem Sansal', null, 'https://books.google.com/books/content?id=Z3XgEQAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 18, 'Tu m''avais promis', 'Maud Ankaoua', null, null),
  ('2026-09-01', 19, 'Le barman du Ritz', 'Philippe Collin', '9791026907619', 'https://books.google.com/books/content?id=Z1Tk0AEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  ('2026-09-01', 20, 'Une pension en Italie', 'Philippe Besson', '9782260056799', 'https://books.google.com/books/content?id=FveTEQAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api')
on conflict (month, rank) do update set
  title = excluded.title, author = excluded.author, isbn = excluded.isbn, cover_url = excluded.cover_url, updated_at = now();
