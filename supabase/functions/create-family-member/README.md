# create-family-member

Ajoute un enfant (sans e-mail) à une carte famille BliGO. Appelée depuis le
back-office (fiche du titulaire) et depuis le profil du titulaire dans l'appli.

## Déploiement (Dashboard Supabase, pas de CLI nécessaire)
1. Supabase > Edge Functions > « Deploy a new function » > « Via Editor ».
2. Nom : `create-family-member` (exactement).
3. Coller le contenu de `index.ts`, puis « Deploy ».
4. Aucun secret à ajouter : SUPABASE_URL, SUPABASE_ANON_KEY et
   SUPABASE_SERVICE_ROLE_KEY sont fournis automatiquement par Supabase.

Prérequis : la migration `sql/add_family_and_digital.sql` doit être exécutée.
