# send-queued-emails

Vide la table `email_outbox` (voir `sql/add_return_reminders_email.sql`) en envoyant
chaque mail via [Resend](https://resend.com). Appelée une fois par jour par pg_cron,
jamais depuis le navigateur.

## Mise en place (une seule fois)

### 1. Compte Resend + domaine vérifié

1. Créer un compte gratuit sur [resend.com](https://resend.com).
2. Dans **Domains**, ajouter `bligo.fr` et suivre les instructions : Resend donne
   2-3 enregistrements DNS (des lignes `TXT` et `MX`/`CNAME` pour SPF/DKIM) à ajouter
   chez Hostinger (hPanel > le domaine `bligo.fr` > Zone DNS). Sans ça, Resend refuse
   d'envoyer depuis une adresse `@bligo.fr` (anti-usurpation).
3. Une fois le domaine marqué "Verified" dans Resend (peut prendre quelques minutes
   à quelques heures selon la propagation DNS), créer une clé API dans **API Keys**.

### 2. Déployer la fonction

Sans la CLI Supabase installée sur cette machine, le plus simple est de passer par
le tableau de bord :

1. Supabase Dashboard > le projet BliGO > **Edge Functions** > **Deploy a new function**.
2. Nom : `send-queued-emails`.
3. Coller le contenu de `index.ts`.
4. Dans **Secrets** de la fonction, ajouter :
   - `RESEND_API_KEY` : la clé créée à l'étape précédente
   - `EMAIL_FROM` : ex. `BliGO <relances@bligo.fr>`

### 3. Brancher le cron

Dans `sql/add_return_reminders_email.sql`, la section 4 contient un
`net.http_post` vers cette fonction avec un `Authorization: Bearer ...` à
compléter avec la **service_role key** du projet (Project Settings > API >
service_role secret — jamais l'anon key, celle-ci doit rester secrète, jamais
dans un fichier committé ni côté navigateur). Une fois les deux placeholders
remplis, exécuter le fichier dans Supabase (SQL Editor > New query > Run).

## Test manuel

Depuis le Dashboard (Edge Functions > send-queued-emails > Invoke), ou :

```bash
curl -X POST 'https://knlymrujmiapzieavzoe.supabase.co/functions/v1/send-queued-emails' \
  -H "Authorization: Bearer <service_role key>"
```

Réponse attendue : `{"sent": N, "failed": 0, "total": N}`.
