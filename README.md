# BliGO — application (Médiathèque de Val-Fleuri)

Application réelle : catalogue, comptes usagers et réservations Click & Collect, connectés à une vraie base de données (Supabase). Pas de build, pas de npm — HTML/CSS/JS natif, ouvrable dans n'importe quel navigateur.

## Mise en route (à faire une seule fois)

1. **Créer le projet Supabase**
   - Va sur [supabase.com](https://supabase.com) et crée un compte gratuit.
   - "New project" → nom : `bligo-valfleuri` → région : Europe (Paris ou Frankfurt, pour rester conforme RGPD) → choisis un mot de passe de base de données (garde-le de côté).

2. **Créer les tables**
   - Dans le projet Supabase, ouvre `SQL Editor` → `New query`.
   - Colle le contenu du fichier `sql/schema.sql` de ce dossier, puis clique `Run`.
   - Ça crée les tables `books` (catalogue), `profiles` (usagers) et `reservations`, avec 8 livres de test déjà chargés.

3. **Connecter l'appli au projet**
   - Dans Supabase : `Project Settings` → `API`.
   - Copie la `Project URL` et la clé `anon public`.
   - Ouvre `js/config.js` dans ce dossier et remplace les deux valeurs.

4. **Lancer l'appli en local**
   ```
   cd app
   python3 -m http.server 8000
   ```
   Puis ouvre `http://localhost:8000` dans le navigateur (ne pas ouvrir le fichier directement en double-cliquant — certains navigateurs bloquent les comptes/connexions sur `file://`).

5. **Tester**
   - Crée un compte usager de test, connecte-toi, réserve un livre.
   - Regarde dans Supabase → `Table Editor` → `reservations` : la réservation doit apparaître en base de données réelle.

## Ce qui est déjà réel

- Comptes usagers (inscription / connexion par e-mail)
- Catalogue de 8 livres (Médiathèque de Val-Fleuri), tous de vrais titres publiés
- Vraies couvertures récupérées en direct via l'API Google Books (pas d'images factices)
- Réservation Click & Collect écrite en base de données
- **Back-office agent** (`admin.html`) : recherche ISBN/titre via Google Books pour cataloguer un livre en un clic, gestion du catalogue (disponibilité, suppression), suivi et mise à jour du statut de toutes les réservations (préparation → prêt → récupéré), session de don (scan de la carte du donateur puis des livres, points de fidélité crédités automatiquement)
- **Espace admin** (`superadmin.html`) : gestion des communes, usagers regroupés par commune (+ liste des inscrits sans commune confirmée), fiche usager (points, réservations, dons), file d'attente des couvertures manquantes avec banque de couvertures réutilisable

### Activer le back-office (à faire une seule fois)

1. Colle le contenu de `sql/add_backoffice.sql` dans Supabase → `SQL Editor` → `Run` (ajoute le rôle `agent` et les permissions associées).
2. Crée un compte usager normal pour la personne qui gère l'accueil (via `index.html`, onglet « Créer un compte »).
3. Dans Supabase → `Table Editor` → `profiles`, trouve sa ligne et passe la colonne `role` de `usager` à `agent`.
4. Cette personne se connecte normalement sur `catalogue.html` : un bouton « Back-office » apparaît dans l'en-tête et mène à `admin.html`.

### Activer l'espace admin (à faire une seule fois)

Réservé à la créatrice de l'application : gestion des communes, usagers par commune, fiche usager (points, dons), couvertures manquantes.

1. Colle le contenu de `sql/add_superadmin_communes.sql` dans Supabase → `SQL Editor` → `Run` (rôle `super_admin`, commune + confirmation sur les profils).
2. Colle ensuite le contenu de `sql/add_donations_and_covers.sql` → `Run` (table des dons, banque de couvertures, bucket de stockage `book-covers`). Si la ligne `insert into storage.buckets` est refusée par l'éditeur SQL, crée le bucket à la main : `Storage` → `New bucket` → nom `book-covers` → Public activé, puis relance uniquement les `create policy` du fichier.
3. Dans Supabase → `Table Editor` → `profiles`, trouve ta ligne et passe la colonne `role` à `super_admin` (ou via SQL : `update profiles set role = 'super_admin' where subscriber_number = '...';`).
4. Connecte-toi normalement : un bouton « Espace admin » apparaît dans l'en-tête et mène à `superadmin.html`. Tu as aussi automatiquement accès à `admin.html` (le rôle `super_admin` hérite des droits `agent`).

## Pas encore fait (prochaines étapes)

- Mise en ligne publique (nom de domaine, hébergement définitif)
- Notifications réelles (SMS / push) à la place de la simulation

On avance module par module à partir de cette base, une fois la connexion Supabase confirmée.
