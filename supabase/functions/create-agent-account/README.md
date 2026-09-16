# create-agent-account

Crée un vrai compte agent (auth Supabase + profil) depuis l'écran « Comptes agents »
de `admin.html`, sans passer par une manipulation SQL manuelle dans Supabase.

Réservée aux comptes **direction** (et à Mégane, super_admin) : la fonction vérifie
elle-même le niveau de l'appelant côté serveur avant de créer quoi que ce soit — le
bouton caché côté interface pour un compte `agent` n'est qu'un confort, pas la
sécurité réelle.

## Mise en place (une seule fois)

Sans la CLI Supabase installée sur cette machine, passer par le tableau de bord :

1. Supabase Dashboard > le projet BliGO > **Edge Functions** > **Deploy a new function**.
2. Nom : `create-agent-account`.
3. Coller le contenu de `index.ts`.
4. Aucun secret à ajouter : `SUPABASE_URL`, `SUPABASE_ANON_KEY` et
   `SUPABASE_SERVICE_ROLE_KEY` sont injectées automatiquement par Supabase pour
   toute Edge Function.
5. Exécuter `sql/add_agent_roles_tariffs_and_age.sql` avant de tester (ajoute
   `profiles.agent_level` et `is_direction()`, utilisés par cette fonction).

## Appel

Depuis `admin.html`, avec un compte direction connecté :

```js
const { data, error } = await supabase.functions.invoke('create-agent-account', {
  body: { full_name, email, password, agent_level, commune_id },
});
```

Réponse : `{ ok: true, user_id }` ou `{ ok: false, message }`.

## Test manuel

```bash
curl -X POST 'https://knlymrujmiapzieavzoe.supabase.co/functions/v1/create-agent-account' \
  -H "Authorization: Bearer <jeton d'un compte direction>" \
  -H "Content-Type: application/json" \
  -d '{"full_name":"Test Agent","email":"test@example.com","password":"motdepasse123","agent_level":"agent","commune_id":1}'
```
