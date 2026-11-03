#!/bin/bash
# Copie les pages usager et l'espace agent (admin.html, depuis le 03/11/2026)
# depuis la racine du dépôt vers www/, prêt pour `cap sync`. superadmin.html
# reste sur ordinateur.
set -e
cd "$(dirname "$0")"
ROOT="../"
DEST="www"

rm -rf "$DEST"
mkdir -p "$DEST"

PAGES="index.html admin.html accueil.html agenda.html liste-envie.html points.html profil.html reservations.html cgu.html confidentialite.html infos.html"
for page in $PAGES; do
  cp "$ROOT$page" "$DEST/"
done

cp -R "$ROOT"css "$DEST/"
cp -R "$ROOT"img "$DEST/"
cp -R "$ROOT"js "$DEST/"

echo "www/ synchronisé depuis la racine du dépôt."
