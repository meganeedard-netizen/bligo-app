// Prépare dist/ pour Tauri : une seule petite page de démarrage.
//
// Depuis le 16/10/2026, le logiciel agent n'embarque plus les pages du
// back-office : il ouvre directement https://bligo.app (admin.html,
// superadmin.html, index.html pour la connexion). Chaque mise en ligne sur
// bligo.app met donc à jour le logiciel Mac et Windows en même temps, sans
// rien réinstaller. Les adaptations propres au logiciel (connexion à chaque
// ouverture, boîtes de dialogue, back-office après connexion) sont dans les
// pages elles-mêmes et s'activent avec « ?logiciel=1 » (voir js/supabaseClient.js).
//
// Cette page de démarrage vérifie que bligo.app répond, puis l'ouvre. Sans
// connexion internet, elle affiche un message avec un bouton « Réessayer ».
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(here, '..');
const DEST = path.join(here, 'dist');
const SITE = 'https://bligo.app';

fs.rmSync(DEST, { recursive: true, force: true });
fs.mkdirSync(path.join(DEST, 'img'), { recursive: true });
fs.copyFileSync(path.join(ROOT, 'img', 'bligo-logo.png'), path.join(DEST, 'img', 'bligo-logo.png'));

fs.writeFileSync(path.join(DEST, 'index.html'), `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>BliGO</title>
  <style>
    html, body { height: 100%; margin: 0; }
    body { display: flex; align-items: center; justify-content: center; background: #FFF8F0; font-family: -apple-system, 'Segoe UI', Roboto, sans-serif; color: #1B4B43; }
    .box { text-align: center; max-width: 360px; padding: 24px; }
    img { width: 160px; height: auto; margin-bottom: 20px; }
    p { font-size: 14px; line-height: 1.5; margin: 0 0 16px; color: rgba(27,75,67,.7); }
    button { background: #1B4B43; color: #fff; border: none; border-radius: 8px; padding: 10px 20px; font-size: 14px; font-weight: 600; cursor: pointer; }
    .hidden { display: none; }
  </style>
</head>
<body>
  <div class="box">
    <img src="img/bligo-logo.png" alt="BliGO">
    <p id="msg">Connexion à BliGO…</p>
    <button id="retry" class="hidden" onclick="start()">Réessayer</button>
  </div>
  <script>
    async function start() {
      document.getElementById('msg').textContent = 'Connexion à BliGO…';
      document.getElementById('retry').classList.add('hidden');
      try {
        const ctrl = new AbortController();
        const timer = setTimeout(() => ctrl.abort(), 10000);
        await fetch('${SITE}/index.html', { mode: 'no-cors', cache: 'no-store', signal: ctrl.signal });
        clearTimeout(timer);
        location.replace('${SITE}/index.html?logiciel=1&t=' + Date.now());
      } catch (e) {
        document.getElementById('msg').textContent = "Pas de connexion à internet, ou BliGO ne répond pas. Vérifie le Wi-Fi ou le câble réseau, puis réessaie.";
        document.getElementById('retry').classList.remove('hidden');
      }
    }
    start();
  </script>
</body>
</html>
`);

console.log('dist/ prêt : page de démarrage qui ouvre ' + SITE + ' (logiciel branché sur le site).');
