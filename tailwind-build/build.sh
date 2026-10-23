#!/bin/bash
# Fabrique css/bligo.css à partir des classes utilisées dans les pages.
# À lancer après toute modification de mise en forme, avant sync-web / mise en ligne.
set -e
cd "$(dirname "$0")"
[ -d node_modules ] || npm install --silent
npx tailwindcss -c tailwind.config.js -i input.css -o ../css/bligo.css --minify
# Module Supabase intégré (js/vendor/supabase.js), version figée dans package.json.
npx esbuild supabase-entry.js --bundle --format=esm --minify --target=es2020 --outfile=../js/vendor/supabase.js --log-level=warning
# QR code de la carte (profil) et lecteur de codes-barres (logiciel agent).
npx esbuild qrcode-entry.js --bundle --format=esm --minify --target=es2020 --outfile=../js/vendor/qrcode.js --log-level=warning
npx esbuild zxing-entry.js --bundle --format=esm --minify --target=es2020 --outfile=../js/vendor/zxing.js --log-level=warning
