#!/bin/bash
# Copie les pages du logiciel agent (admin.html, superadmin.html, index.html
# pour la connexion) depuis la racine du dépôt vers dist/, prêt pour Tauri.
set -e
cd "$(dirname "$0")"
ROOT="../"
DEST="dist"

rm -rf "$DEST"
mkdir -p "$DEST"

PAGES="index.html admin.html superadmin.html"
for page in $PAGES; do
  cp "$ROOT$page" "$DEST/"
done

cp -R "$ROOT"css "$DEST/"
cp -R "$ROOT"img "$DEST/"
cp -R "$ROOT"js "$DEST/"

# index.html redirige normalement vers accueil.html après connexion (page
# usager) — absente de ce paquet, réservé aux agents. On route plutôt vers
# admin.html ou superadmin.html selon le rôle, sans toucher au index.html
# source (utilisé tel quel par le vrai site usager bligo.app).
perl -0777 -pi.bak -e "s/window\.location\.href = 'accueil\.html';/redirectAfterLogin();/g" "$DEST/index.html"
perl -0777 -pi.bak -e "s{(</script>\s*</body>)}{
  window.redirectAfterLogin = async function () {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return;
    const { data: profile } = await supabase.from('profiles').select('role').eq('id', session.user.id).single();
    window.location.href = profile?.role === 'super_admin' ? 'superadmin.html' : 'admin.html';
  };
\$1}" "$DEST/index.html"

# window.alert() et window.confirm() ne fonctionnent pas nativement dans la
# webview de Tauri (pas de boîte système par défaut) — le bouton "Supprimer"
# (confirm()) ne faisait donc jamais rien, silencieusement. Remplacés ici par
# de vraies boîtes de dialogue HTML, uniquement dans le paquet Tauri (le vrai
# site fonctionne déjà très bien avec les boîtes natives du navigateur).
for page in admin.html superadmin.html; do
  perl -0777 -pi.bak -e "s/confirm\(/await confirmDialog(/g" "$DEST/$page"
  # addDraftFromIsbn n'était pas async (seul appelant de confirm() en dehors
  # d'une fonction déjà async) — le devient ici pour pouvoir faire le await
  # ci-dessus, sans changer sa signature dans le code source (ses appelants
  # ne l'attendent déjà pas).
  perl -0777 -pi.bak -e "s/function addDraftFromIsbn\(rawCode\) \{/async function addDraftFromIsbn(rawCode) {/" "$DEST/$page"
  perl -0777 -pi.bak -e "s{(</head>)}{<script>
    function bligoDialogBackdrop() {
      const backdrop = document.createElement('div');
      backdrop.style.cssText = 'position:fixed;inset:0;z-index:99999;background:rgba(27,75,67,.4);display:flex;align-items:center;justify-content:center;padding:16px;';
      return backdrop;
    }
    function bligoEscapeHtml(s) {
      return String(s ?? '').replace(/[&<>\"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',\"'\":'&#39;'}[c]));
    }
    window.alert = function (message) {
      const backdrop = bligoDialogBackdrop();
      backdrop.innerHTML = '<div style=\"background:#fff;border-radius:16px;box-shadow:0 20px 40px rgba(0,0,0,.2);max-width:380px;width:100%;padding:20px;\">' +
        '<p style=\"font-size:14px;color:#1B4B43;white-space:pre-wrap;line-height:1.5;margin:0 0 16px;\">' + bligoEscapeHtml(message) + '</p>' +
        '<button style=\"width:100%;background:#1B4B43;color:#fff;border:none;border-radius:8px;padding:10px;font-size:14px;font-weight:600;cursor:pointer;\">OK</button></div>';
      backdrop.querySelector('button').onclick = () => backdrop.remove();
      document.body.appendChild(backdrop);
    };
    window.confirmDialog = function (message) {
      return new Promise((resolve) => {
        const backdrop = bligoDialogBackdrop();
        backdrop.innerHTML = '<div style=\"background:#fff;border-radius:16px;box-shadow:0 20px 40px rgba(0,0,0,.2);max-width:380px;width:100%;padding:20px;\">' +
          '<p style=\"font-size:14px;color:#1B4B43;white-space:pre-wrap;line-height:1.5;margin:0 0 16px;\">' + bligoEscapeHtml(message) + '</p>' +
          '<div style=\"display:flex;gap:8px;\"><button data-a=\"cancel\" style=\"flex:1;background:#f4f4f4;color:#1B4B43;border:none;border-radius:8px;padding:10px;font-size:14px;font-weight:600;cursor:pointer;\">Annuler</button>' +
          '<button data-a=\"ok\" style=\"flex:1;background:#F07F14;color:#fff;border:none;border-radius:8px;padding:10px;font-size:14px;font-weight:600;cursor:pointer;\">Confirmer</button></div></div>';
        backdrop.querySelector('[data-a=\"cancel\"]').onclick = () => { backdrop.remove(); resolve(false); };
        backdrop.querySelector('[data-a=\"ok\"]').onclick = () => { backdrop.remove(); resolve(true); };
        document.body.appendChild(backdrop);
      });
    };
  </script>
\$1}" "$DEST/$page"
done

# Sous Windows, Perl exige une copie de sauvegarde pour modifier un fichier
# en place (-pi.bak) : on la supprime aussitôt.
rm -f "$DEST"/*.bak

echo "dist/ synchronisé depuis la racine du dépôt (index.html adapté pour rediriger vers admin/superadmin, alert/confirm remplacés)."
