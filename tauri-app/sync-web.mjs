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
for (const dir of ['css', 'img', 'js']) {
  fs.cpSync(path.join(ROOT, dir), path.join(DEST, dir), { recursive: true });
}

const edit = (page, fn) => {
  const file = path.join(DEST, page);
  fs.writeFileSync(file, fn(fs.readFileSync(file, 'utf8')));
};

// index.html redirige normalement vers accueil.html après connexion (page
// usager) — absente de ce paquet, réservé aux agents. On route plutôt vers
// admin.html ou superadmin.html selon le rôle, sans toucher au index.html
// source (utilisé tel quel par le vrai site usager bligo.app).
const INDEX_INJECT = "\n  window.redirectAfterLogin = async function () {\n    const { data: { session } } = await supabase.auth.getSession();\n    if (!session) return;\n    const { data: profile } = await supabase.from('profiles').select('role').eq('id', session.user.id).single();\n    window.location.href = profile?.role === 'super_admin' ? 'superadmin.html' : 'admin.html';\n  };\n";
edit('index.html', html => html
  .replace(/window\.location\.href = 'accueil\.html';/g, 'redirectAfterLogin();')
  .replace(/(<\/script>\s*<\/body>)/, (m) => INDEX_INJECT + m));

// window.alert() et window.confirm() ne fonctionnent pas nativement dans la
// webview de Tauri (pas de boîte système par défaut) — remplacés ici par de
// vraies boîtes de dialogue HTML, uniquement dans le paquet Tauri (le vrai
// site fonctionne déjà très bien avec les boîtes natives du navigateur).
const HEAD_INJECT = "<script>\n    function bligoDialogBackdrop() {\n      const backdrop = document.createElement('div');\n      backdrop.style.cssText = 'position:fixed;inset:0;z-index:99999;background:rgba(27,75,67,.4);display:flex;align-items:center;justify-content:center;padding:16px;';\n      return backdrop;\n    }\n    function bligoEscapeHtml(s) {\n      return String(s ?? '').replace(/[&<>\"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',\"'\":'&#39;'}[c]));\n    }\n    window.alert = function (message) {\n      const backdrop = bligoDialogBackdrop();\n      backdrop.innerHTML = '<div style=\"background:#fff;border-radius:16px;box-shadow:0 20px 40px rgba(0,0,0,.2);max-width:380px;width:100%;padding:20px;\">' +\n        '<p style=\"font-size:14px;color:#1B4B43;white-space:pre-wrap;line-height:1.5;margin:0 0 16px;\">' + bligoEscapeHtml(message) + '</p>' +\n        '<button style=\"width:100%;background:#1B4B43;color:#fff;border:none;border-radius:8px;padding:10px;font-size:14px;font-weight:600;cursor:pointer;\">OK</button></div>';\n      backdrop.querySelector('button').onclick = () => backdrop.remove();\n      document.body.appendChild(backdrop);\n    };\n    window.confirmDialog = function (message) {\n      return new Promise((resolve) => {\n        const backdrop = bligoDialogBackdrop();\n        backdrop.innerHTML = '<div style=\"background:#fff;border-radius:16px;box-shadow:0 20px 40px rgba(0,0,0,.2);max-width:380px;width:100%;padding:20px;\">' +\n          '<p style=\"font-size:14px;color:#1B4B43;white-space:pre-wrap;line-height:1.5;margin:0 0 16px;\">' + bligoEscapeHtml(message) + '</p>' +\n          '<div style=\"display:flex;gap:8px;\"><button data-a=\"cancel\" style=\"flex:1;background:#f4f4f4;color:#1B4B43;border:none;border-radius:8px;padding:10px;font-size:14px;font-weight:600;cursor:pointer;\">Annuler</button>' +\n          '<button data-a=\"ok\" style=\"flex:1;background:#F07F14;color:#fff;border:none;border-radius:8px;padding:10px;font-size:14px;font-weight:600;cursor:pointer;\">Confirmer</button></div></div>';\n        backdrop.querySelector('[data-a=\"cancel\"]').onclick = () => { backdrop.remove(); resolve(false); };\n        backdrop.querySelector('[data-a=\"ok\"]').onclick = () => { backdrop.remove(); resolve(true); };\n        document.body.appendChild(backdrop);\n      });\n    };\n  </script>\n";
for (const page of ['admin.html', 'superadmin.html']) {
  edit(page, html => html
    .replace(/confirm\(/g, 'await confirmDialog(')
    // addDraftFromIsbn n'était pas async (seul appelant de confirm() en dehors
    // d'une fonction déjà async) — le devient ici pour pouvoir faire le await.
    .replace(/function addDraftFromIsbn\(rawCode\) \{/, 'async function addDraftFromIsbn(rawCode) {')
    .replace(/(<\/head>)/, (m) => HEAD_INJECT + m));
}

console.log('dist/ synchronisé depuis la racine du dépôt (index.html adapté pour rediriger vers admin/superadmin, alert/confirm remplacés).');
