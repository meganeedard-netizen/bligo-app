// Copie les pages du logiciel agent (admin.html, superadmin.html, index.html
// pour la connexion) depuis la racine du dépôt vers dist/, prêt pour Tauri.
//
// Réécrit en JavaScript le 09/10/2026 (ancien sync-web.sh en bash + perl) :
// le même script tourne à l'identique sur Mac et sur la machine Windows de
// GitHub Actions, sans dépendre de bash, de perl ni des fins de ligne.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(here, '..');
const DEST = path.join(here, 'dist');

fs.rmSync(DEST, { recursive: true, force: true });
fs.mkdirSync(DEST, { recursive: true });
for (const page of ['index.html', 'admin.html', 'superadmin.html']) {
  fs.copyFileSync(path.join(ROOT, page), path.join(DEST, page));
}
// css/ est vide aujourd'hui : git ne garde pas les dossiers vides, il n'existe
// donc pas sur la machine de GitHub. Un dossier absent est simplement ignoré.
for (const dir of ['css', 'img', 'js']) {
  const src = path.join(ROOT, dir);
  if (fs.existsSync(src)) fs.cpSync(src, path.join(DEST, dir), { recursive: true });
}

const edit = (page, fn) => {
  const file = path.join(DEST, page);
  fs.writeFileSync(file, fn(fs.readFileSync(file, 'utf8')));
};

// index.html redirige normalement vers accueil.html après connexion (page
// usager) — absente de ce paquet, réservé aux agents. On route plutôt vers
// admin.html ou superadmin.html selon le rôle, sans toucher au index.html
// source (utilisé tel quel par le vrai site usager bligo.app).
const INDEX_INJECT = "\n  window.redirectAfterLogin = async function () {\n    const { data: { session } } = await supabase.auth.getSession();\n    if (!session) return;\n    const { data: profile } = await supabase.from('profiles').select('role').eq('id', session.user.id).single();\n    window.location.href = profile?.role === 'super_admin' ? 'superadmin.html' : 'admin.html';\n  };\n" +
  // Logiciel réservé aux agents (12/10/2026) : connexion seulement. Pas de choix
  // de médiathèque ni de création de compte (c'est Mégane qui crée les comptes
  // agents) ; un compte usager qui se connecte est refusé avec un message.
  "  window.BLIGO_AGENT_APP = true;\n" +
  "  document.getElementById('landing-choice')?.classList.add('hidden');\n" +
  "  document.getElementById('auth-card')?.classList.remove('hidden');\n" +
  "  document.getElementById('auth-card')?.classList.add('flex');\n" +
  "  document.querySelector('#form-login [onclick=\"switchTab(\\'signup\\')\"]')?.parentElement.classList.add('hidden');\n" +
  "  document.getElementById('tab-login')?.parentElement.classList.add('hidden');\n" +
  "  document.querySelector('#auth-card > button[onclick=\"backToBrowsing()\"]')?.classList.add('hidden');\n" +
  "  switchTab('login');\n" +
  "  if (new URLSearchParams(location.search).get('not_agent')) {\n" +
  "    messageEl.textContent = 'Ce compte n\\'a pas accès au back-office.';\n" +
  "    messageEl.className = 'text-xs text-center mt-3 text-red-600';\n" +
  "  }\n";
edit('index.html', html => html
  .replace(/window\.location\.href = 'accueil\.html';/g, 'redirectAfterLogin();')
  .replace(/(<\/script>\s*<\/body>)/, (m) => INDEX_INJECT + m));

// window.alert() et window.confirm() ne fonctionnent pas nativement dans la
// webview de Tauri (pas de boîte système par défaut) — remplacés ici par de
// vraies boîtes de dialogue HTML, uniquement dans le paquet Tauri (le vrai
// site fonctionne déjà très bien avec les boîtes natives du navigateur).
const HEAD_INJECT = "<script>\n    window.BLIGO_AGENT_APP = true;\n    function bligoDialogBackdrop() {\n      const backdrop = document.createElement('div');\n      backdrop.style.cssText = 'position:fixed;inset:0;z-index:99999;background:rgba(27,75,67,.4);display:flex;align-items:center;justify-content:center;padding:16px;';\n      return backdrop;\n    }\n    function bligoEscapeHtml(s) {\n      return String(s ?? '').replace(/[&<>\"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',\"'\":'&#39;'}[c]));\n    }\n    window.alert = function (message) {\n      const backdrop = bligoDialogBackdrop();\n      backdrop.innerHTML = '<div style=\"background:#fff;border-radius:16px;box-shadow:0 20px 40px rgba(0,0,0,.2);max-width:380px;width:100%;padding:20px;\">' +\n        '<p style=\"font-size:14px;color:#1B4B43;white-space:pre-wrap;line-height:1.5;margin:0 0 16px;\">' + bligoEscapeHtml(message) + '</p>' +\n        '<button style=\"width:100%;background:#1B4B43;color:#fff;border:none;border-radius:8px;padding:10px;font-size:14px;font-weight:600;cursor:pointer;\">OK</button></div>';\n      backdrop.querySelector('button').onclick = () => backdrop.remove();\n      document.body.appendChild(backdrop);\n    };\n    window.confirmDialog = function (message) {\n      return new Promise((resolve) => {\n        const backdrop = bligoDialogBackdrop();\n        backdrop.innerHTML = '<div style=\"background:#fff;border-radius:16px;box-shadow:0 20px 40px rgba(0,0,0,.2);max-width:380px;width:100%;padding:20px;\">' +\n          '<p style=\"font-size:14px;color:#1B4B43;white-space:pre-wrap;line-height:1.5;margin:0 0 16px;\">' + bligoEscapeHtml(message) + '</p>' +\n          '<div style=\"display:flex;gap:8px;\"><button data-a=\"cancel\" style=\"flex:1;background:#f4f4f4;color:#1B4B43;border:none;border-radius:8px;padding:10px;font-size:14px;font-weight:600;cursor:pointer;\">Annuler</button>' +\n          '<button data-a=\"ok\" style=\"flex:1;background:#F07F14;color:#fff;border:none;border-radius:8px;padding:10px;font-size:14px;font-weight:600;cursor:pointer;\">Confirmer</button></div></div>';\n        backdrop.querySelector('[data-a=\"cancel\"]').onclick = () => { backdrop.remove(); resolve(false); };\n        backdrop.querySelector('[data-a=\"ok\"]').onclick = () => { backdrop.remove(); resolve(true); };\n        document.body.appendChild(backdrop);\n      });\n    };\n  </script>\n";
for (const page of ['admin.html', 'superadmin.html']) {
  edit(page, html => html
    .replace(/confirm\(/g, 'await confirmDialog(')
    // addDraftFromIsbn n'était pas async (seul appelant de confirm() en dehors
    // d'une fonction déjà async) — le devient ici pour pouvoir faire le await.
    .replace(/function addDraftFromIsbn\(rawCode\) \{/, 'async function addDraftFromIsbn(rawCode) {')
    .replace(/(<\/head>)/, (m) => HEAD_INJECT + m));
}

console.log('dist/ synchronisé depuis la racine du dépôt (index.html adapté pour rediriger vers admin/superadmin, alert/confirm remplacés).');

// Garde-fou (12/10/2026) : une fonction non « async » qui reçoit un
// « await confirmDialog( » casse tout le script de la page dans le logiciel.
// On vérifie la syntaxe de chaque page et on arrête la fabrication si besoin.
import { execFileSync } from 'node:child_process';
import os from 'node:os';
for (const page of ['index.html', 'admin.html', 'superadmin.html']) {
  const html = fs.readFileSync(path.join(DEST, page), 'utf8');
  const code = [...html.matchAll(/<script type="module">([\s\S]*?)<\/script>/g)].map(m => m[1]).join('\n');
  const tmp = path.join(os.tmpdir(), `bligo-check-${page}.mjs`);
  fs.writeFileSync(tmp, code);
  try {
    execFileSync(process.execPath, ['--check', tmp], { stdio: 'pipe' });
  } catch (e) {
    console.error(`Erreur de syntaxe dans ${page} (version logiciel) :\n${e.stderr}`);
    process.exit(1);
  }
}
console.log('Syntaxe des pages vérifiée.');
