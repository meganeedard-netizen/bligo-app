# prepare-cover

Prépare la couverture d'un livre scanné, selon la règle de Mégane (26/10/2026) :
pleine page au format 2:3 (pour les coins arrondis de l'appli), vraie face
avant, jamais une image vide ou une fausse image ; sinon, photo prise par
l'agent.

Ordre des sources : l'image proposée par l'API, puis Open Library et Google
Books (sites des éditeurs retirés le 26/11/2026). L'image retenue est
débarrassée de ses bandes unies, mise en 600x900 sans déformation (fond flou
si son format n'est pas celui d'un roman) et rangée dans le bucket
`book-covers` (dossier `covers/`).

## Mise en place (une seule fois)

1. Supabase Dashboard > le projet BliGO > **Edge Functions** > **Deploy a new function**.
2. Nom : `prepare-cover`.
3. Coller le contenu de `index.ts`.
4. Aucun secret à ajouter (`SUPABASE_URL`, `SUPABASE_ANON_KEY` et
   `SUPABASE_SERVICE_ROLE_KEY` sont injectées automatiquement).

Tant qu'elle n'est pas déployée, le logiciel garde l'ancien fonctionnement
(couverture de l'API telle quelle).

## Appel

Depuis `admin.html` (`insertBook` au catalogage, `backfillIncompleteBooks` en
arrière-plan) :

```js
const { data } = await supabase.functions.invoke('prepare-cover', {
  body: { cover_url, isbn, title },
});
// data => { ok: true, cover_url, color: 'Couleur' | 'Noir et blanc', source }
//      ou { ok: false, input_checked, message }
```

## Limites connues

- Une photo du livre en 3D (tranche visible) n'est pas détectée : elle est
  seulement recadrée. 
- Sans couverture trouvée, l'agent photographie le document dans le logiciel.
