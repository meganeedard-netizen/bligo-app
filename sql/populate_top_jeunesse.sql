-- BliGO — Top Jeunesse (14/09/2026)
-- 20 titres jeunesse de référence, saisis par Mégane.
-- Couvertures et ISBN récupérés automatiquement via Google Books (Open Library en appoint).
-- Prérequis : sql/add_top_jeunesse.sql
-- À exécuter dans Supabase : Project > SQL Editor > New query > coller > Run

insert into public.top_jeunesse_books (rank, title, author, age_range, genre, isbn, cover_url) values
  (1, 'Harry Potter à l''école des sorciers', 'J.K. Rowling', '10-15 ans', 'Fantasy', null, 'https://books.google.com/books/content?id=I_ApAQAAMAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (2, 'Mortelle Adèle (Série)', 'Mr Tan & Diane Le Feyer', '7-11 ans', 'BD & Roman', '9782494678767', 'https://books.google.com/books/content?id=aEjTEQAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (3, 'Gardiens des Cités Perdues', 'Shannon Messenger', '10-14 ans', 'Fantasy', '9782371021907', 'https://books.google.com/books/content?id=vVJtDwAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (4, 'Le Journal d''un dégonflé', 'Jeff Kinney', '9-12 ans', 'Humour', '9791023512335', 'https://books.google.com/books/content?id=aE3qDwAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (5, 'Le Petit Prince', 'Antoine de Saint-Exupéry', 'Tous publics', 'Conte', null, 'https://books.google.com/books/content?id=t6LttwEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (6, 'Chair de poule (Série)', 'R.L. Stine', '9-12 ans', 'Frisson', '9791036360022', 'https://books.google.com/books/content?id=pW2xEAAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (7, 'Hunger Games (Saga)', 'Suzanne Collins', '13-18 ans', 'Dystopie', null, 'https://books.google.com/books/content?id=kCIAswEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (8, 'La Passe-miroir (Tétralogie)', 'Christelle Dabos', '12-18 ans', 'Fantasy', '9782075164252', 'https://books.google.com/books/content?id=VJmeEQAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (9, 'Percy Jackson (Saga)', 'Rick Riordan', '10-14 ans', 'Mythologie', '9782019109950', 'https://books.google.com/books/content?id=UaQUvgAACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (10, 'Les Carnets de Cerise', 'Joris Chamblain & Aurélie Neyret', '9-13 ans', 'BD & Enquête', '9782302044708', 'https://books.google.com/books/content?id=owgxBQAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (11, 'Ewilan (Sagas)', 'Pierre Bottero', '11-15 ans', 'Fantasy', '9782700239881', 'https://books.google.com/books/content?id=IAOLfPsERrkC&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (12, 'Charlie et la Chocolaterie', 'Roald Dahl', '8-11 ans', 'Roman jeunesse', '9782070601578', 'https://books.google.com/books/content?id=9SanDAEACAAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (13, 'Twilight (Saga)', 'Stephenie Meyer', '13-18 ans', 'Romance fantastique', null, 'https://books.google.com/books/content?id=TsVmBAAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (14, 'Tobie Lolness', 'Timothée de Fombelle', '10-14 ans', 'Aventure', null, 'https://covers.openlibrary.org/b/id/13265646-L.jpg'),
  (15, 'Les Enfants de la Résistance', 'Vincent Dugomier & Benoît Ers', '9-14 ans', 'BD Histoire', '9782808211086', 'https://books.google.com/books/content?id=Xkt-EAAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (16, 'Nos étoiles contraires', 'John Green', '13-18 ans', 'Roman ados', '9782092543085', 'https://books.google.com/books/content?id=nJiUvMO1gFUC&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (17, 'Divergente (Saga)', 'Veronica Roth', '13-18 ans', 'Dystopie', null, 'https://books.google.com/books/content?id=uaWrUISCo_MC&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (18, 'Les Chroniques de Narnia', 'C.S. Lewis', '9-13 ans', 'Fantasy', '9782075037501', 'https://books.google.com/books/content?id=ZQdIAQAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (19, 'Le Lion', 'Joseph Kessel', '10-14 ans', 'Classique', '9782075058278', 'https://books.google.com/books/content?id=v6WOCgAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api'),
  (20, 'À contre-sens (Culpables)', 'Mercedes Ron', '14-18 ans', 'Romance YA', '9782017078760', 'https://books.google.com/books/content?id=8XaZDwAAQBAJ&printsec=frontcover&img=1&zoom=1&source=gbs_api')
on conflict (rank) do update set
  title = excluded.title, author = excluded.author, age_range = excluded.age_range, genre = excluded.genre, isbn = excluded.isbn, cover_url = excluded.cover_url, updated_at = now();
