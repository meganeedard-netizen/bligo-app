#!/bin/bash
# Fabrique css/bligo.css à partir des classes utilisées dans les pages.
# À lancer après toute modification de mise en forme, avant sync-web / mise en ligne.
set -e
cd "$(dirname "$0")"
[ -d node_modules ] || npm install --silent
npx tailwindcss -c tailwind.config.js -i input.css -o ../css/bligo.css --minify
