// BliGO — Auto-détection couverture couleur / noir et blanc (16/09/2026)
//
// Le navigateur ne peut pas analyser les pixels d'une couverture Google Books :
// ces images n'ont aucun en-tête CORS, donc <canvas> bloque la lecture (vérifié
// en direct le 15/09/2026, voir la mémoire du projet). Cette fonction contourne
// le blocage en récupérant l'image côté serveur, où CORS ne s'applique pas.
//
// Appelée depuis admin.html (fiche livre) via
// supabase.functions.invoke('detect-cover-color', { body: { cover_url } }).
//
// Restreinte aux hébergeurs de couvertures connus de BliGO (Google Books,
// Open Library, Supabase Storage) : cette fonction accepte une URL fournie par
// le client et la récupère depuis le serveur, ce qui serait une porte ouverte
// au SSRF (le serveur irait chercher n'importe quelle URL interne) sans cette
// liste blanche.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

const ALLOWED_HOST_SUFFIXES = [
  'books.google.com',
  'googleusercontent.com',
  'covers.openlibrary.org',
  '.supabase.co',
];

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

function isAllowedHost(hostname: string) {
  return ALLOWED_HOST_SUFFIXES.some((suffix) => hostname === suffix || hostname.endsWith('.' + suffix) || hostname.endsWith(suffix));
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ ok: false, message: 'Méthode non supportée' }, 405);

  const authHeader = req.headers.get('Authorization') ?? '';
  const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user: caller }, error: authError } = await callerClient.auth.getUser();
  if (authError || !caller) return json({ ok: false, message: 'Non authentifié' }, 401);

  let body: { cover_url?: string };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, message: 'Corps de requête invalide' }, 400);
  }

  const coverUrl = body.cover_url;
  if (!coverUrl) return json({ ok: false, message: 'cover_url manquant' }, 400);

  let parsed: URL;
  try {
    parsed = new URL(coverUrl);
  } catch {
    return json({ ok: false, message: 'URL invalide' }, 400);
  }
  if (parsed.protocol !== 'https:' || !isAllowedHost(parsed.hostname)) {
    return json({ ok: false, message: "Source d'image non reconnue" }, 400);
  }

  let bytes: Uint8Array;
  try {
    const res = await fetch(parsed.toString());
    if (!res.ok) return json({ ok: false, message: `Image inaccessible (${res.status})` }, 502);
    bytes = new Uint8Array(await res.arrayBuffer());
  } catch (err) {
    return json({ ok: false, message: 'Échec du téléchargement : ' + String(err) }, 502);
  }

  let image: Image;
  try {
    image = await Image.decode(bytes);
  } catch (err) {
    return json({ ok: false, message: "Format d'image non supporté : " + String(err) }, 422);
  }

  // Redimensionnée en petit : suffisant pour juger couleur/N&B, et beaucoup
  // plus rapide à parcourir pixel par pixel qu'une couverture pleine taille.
  const small = image.resize(32, Image.RESIZE_AUTO);

  let totalDiff = 0;
  let pixelCount = 0;
  for (const [, , color] of small.iterateWithColors()) {
    const [r, g, b] = Image.colorToRGBA(color);
    const diff = Math.max(r, g, b) - Math.min(r, g, b);
    totalDiff += diff;
    pixelCount++;
  }

  const avgDiff = pixelCount ? totalDiff / pixelCount : 0;
  // Seuil choisi empiriquement : une vraie couverture N&B (scan ou impression
  // grise) a un écart moyen entre canaux proche de 0, une couverture couleur
  // dépasse largement 10 même pour des teintes pastel.
  const color = avgDiff > 10 ? 'Couleur' : 'Noir et blanc';

  return json({ ok: true, color, avg_channel_diff: Math.round(avgDiff * 10) / 10 });
});
