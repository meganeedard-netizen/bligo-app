#!/bin/bash
# Copie les pages usager (pas admin.html/superadmin.html, réservés au logiciel
# agent sur Tauri) depuis la racine du dépôt vers www/, prêt pour `cap sync`.
set -e
cd "$(dirname "$0")"
ROOT="../"
DEST="www"

rm -rf "$DEST"
mkdir -p "$DEST"

PAGES="index.html accueil.html agenda.html liste-envie.html points.html profil.html reservations.html"
for page in $PAGES; do
  cp "$ROOT$page" "$DEST/"
done

cp -R "$ROOT"css "$DEST/"
cp -R "$ROOT"img "$DEST/"
cp -R "$ROOT"js "$DEST/"

# profil.html propose un raccourci vers admin.html/superadmin.html pour les
# comptes agent/super_admin — ces pages n'existent pas dans ce paquet
# (réservées au logiciel de bureau sur Tauri). Retire le bloc HTML ET son
# activation JS ensemble : les laisser dissociés ferait planter classList sur
# un élément inexistant, et casserait tout le reste de la page (points, nom…)
# pour les comptes agent/admin.
perl -0777 -pi -e "s{\s*<div id=\"agent-section\".*?</div>\n}{}s" "$DEST/profil.html"
perl -0777 -pi -e "s{\s*if \(profile\?\.role === 'agent'.*?superadmin-link'\)\.classList\.remove\('hidden'\);\s*\}\n}{\n}s" "$DEST/profil.html"

echo "www/ synchronisé depuis la racine du dépôt (raccourci back-office retiré de profil.html)."
