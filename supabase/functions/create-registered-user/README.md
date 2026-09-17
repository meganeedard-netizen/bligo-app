# create-registered-user

Crée un compte inscrit directement confirmé, depuis l'écran **Inscrits** de
`admin.html`, pour une personne qui n'a pas l'application (bouton
« + Ajouter un inscrit »). Contrairement à une préinscription en ligne, le
compte est actif immédiatement — l'agent vérifie l'identité en personne au
moment de la saisie.

Ouverte à n'importe quel agent (pas seulement direction) : ajouter un inscrit
est une tâche de guichet courante.

## Mise en place (une seule fois)

1. Supabase Dashboard > le projet BliGO > **Edge Functions** > **Deploy a new function**.
2. Nom : `create-registered-user`.
3. Coller le contenu de `index.ts`.
4. Aucun secret à ajouter (`SUPABASE_URL`, `SUPABASE_ANON_KEY` et
   `SUPABASE_SERVICE_ROLE_KEY` sont injectées automatiquement).

## Appel

Depuis `admin.html`, avec un compte agent connecté :

```js
const { data, error } = await supabase.functions.invoke('create-registered-user', {
  body: { full_name, email, password, tariff_category, commune_id },
});
```

Réponse : `{ ok: true, user_id }` ou `{ ok: false, message }`.

## Test manuel

```bash
curl -X POST 'https://knlymrujmiapzieavzoe.supabase.co/functions/v1/create-registered-user' \
  -H "Authorization: Bearer <jeton d'un compte agent>" \
  -H "Content-Type: application/json" \
  -d '{"full_name":"Test Inscrit","email":"test-inscrit@example.com","password":"motdepasse123","tariff_category":"majeur","commune_id":1}'
```
