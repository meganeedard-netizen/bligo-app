# detect-cover-color

Détecte automatiquement si la couverture d'un livre est en couleur ou en noir
et blanc, en analysant l'image — pas le texte. Contourne le blocage CORS de
Google Books en récupérant l'image côté serveur (voir `index.ts` pour le détail
du problème).

## Mise en place (une seule fois)

1. Supabase Dashboard > le projet BliGO > **Edge Functions** > **Deploy a new function**.
2. Nom : `detect-cover-color`.
3. Coller le contenu de `index.ts`.
4. Aucun secret à ajouter (`SUPABASE_URL`/`SUPABASE_ANON_KEY` injectées automatiquement).

## Appel

Depuis la fiche livre de `admin.html`, bouton « Détecter automatiquement » à
côté du champ Couverture :

```js
const { data, error } = await supabase.functions.invoke('detect-cover-color', {
  body: { cover_url: book.cover_url },
});
// data => { ok: true, color: 'Couleur' | 'Noir et blanc', avg_channel_diff }
```

Si `ok` est `false` (format d'image non supporté, image inaccessible, source
non reconnue), l'agent garde la sélection manuelle comme aujourd'hui.

## Test manuel

```bash
curl -X POST 'https://knlymrujmiapzieavzoe.supabase.co/functions/v1/detect-cover-color' \
  -H "Authorization: Bearer <jeton d'un compte agent>" \
  -H "Content-Type: application/json" \
  -d '{"cover_url":"https://covers.openlibrary.org/b/isbn/9782070360024-L.jpg"}'
```
