-- Couvertures trouvées sur Google Books pour les livres hors condition
-- (Bibliothèque Libre) qui n'en avaient pas encore. "Contes et légendes de
-- Guadeloupe" (Collectif) n'a pas de correspondance fiable sur Google Books —
-- laissé de côté, il garde son affichage par défaut (initiale colorée).

update public.free_books set cover_url = 'https://books.google.com/books/content?id=t6LttwEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'
  where title = 'Le Petit Prince' and author = 'Antoine de Saint-Exupéry';

update public.free_books set cover_url = 'https://books.google.com/books/content?id=ZbCLEAAAQBAJ&printsec=frontcover&img=1&zoom=1&edge=curl&source=gbs_api'
  where title = 'Vingt mille lieues sous les mers' and author = 'Jules Verne';

update public.free_books set cover_url = 'https://books.google.com/books/content?id=yEq6EAAAQBAJ&printsec=frontcover&img=1&zoom=1&edge=curl&source=gbs_api'
  where title = 'Notre-Dame de Paris' and author = 'Victor Hugo';

update public.free_books set cover_url = 'https://books.google.com/books/content?id=jlXzEAAAQBAJ&printsec=frontcover&img=1&zoom=1&edge=curl&source=gbs_api'
  where title = 'Le Comte de Monte-Cristo' and author = 'Alexandre Dumas';
