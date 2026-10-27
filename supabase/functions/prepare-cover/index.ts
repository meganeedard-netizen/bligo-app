// BliGO - Préparation automatique des couvertures au catalogage (26/10/2026)
//
// Règle de Mégane : une couverture dans l'appli est toujours en pleine page,
// au format 2:3 (pour que les coins arrondis s'appliquent), la vraie face
// avant, jamais une image vide ou une fausse image. Si l'API ne donne rien de
// bon, aller la chercher chez l'éditeur.
//
// Ce que fait la fonction, pour un livre scanné :
// 1. essaie la couverture proposée par l'API (Google Books / Open Library),
//    puis les sites éditeurs (adresses construites avec l'ISBN), puis Open
//    Library et Google Books en lecture directe ;
// 2. écarte l'image « non disponible » de Google et les images trop petites ;
// 3. retire les bandes de couleur unie autour (image carrée avec bandes
//    blanches, cadre) et met l'image en 600x900 plein cadre ;
// 4. l'enregistre dans le bucket book-covers et renvoie son adresse publique,
//    avec la couleur / noir et blanc (même règle que detect-cover-color).
//
// Appelée depuis admin.html (insertBook et rattrapage en arrière-plan) via
// supabase.functions.invoke('prepare-cover', { body: { cover_url, isbn, title } }).
//
// Les adresses récupérées sont soit construites ici (éditeurs, Open Library,
// Google), soit fournies par le client mais limitées à la liste blanche
// ci-dessous, pour ne pas ouvrir de porte SSRF (voir detect-cover-color).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const ALLOWED_HOST_SUFFIXES = ['books.google.com', 'googleusercontent.com', 'covers.openlibrary.org', 'archive.org', '.supabase.co'];
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/130 Safari/537.36';
const OUT_W = 600, OUT_H = 900;

// Image « image not available » de Google Books (vérifié le 26/10/2026 : même
// fichier renvoyé pour tous les livres sans vraie couverture, en zoom 0 et 1).
const GOOGLE_PLACEHOLDER_SIZES = new Set(['575x750', '128x170']);

// Codes Interforum (diffuseur Editis) vérifiés le 26/10/2026 sur de vrais
// livres : Pocket, La Découverte/Zones, Plon, Tana. Les autres sont des essais
// peu coûteux (une requête en 404 si le code n'existe pas).
const INTERFORUM_CODES = ['POC', 'DEC', 'PLO', 'TAN', 'FIR', 'LAF', 'NIL', 'JUL', 'SEG', 'ROB', 'PRE', 'BEL', '1018', 'PKT'];

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}

function isAllowedHost(hostname: string) {
  return ALLOWED_HOST_SUFFIXES.some((s) => hostname === s || hostname.endsWith('.' + s) || hostname.endsWith(s));
}

function slugify(s: string) {
  return (s || '').split(' : ')[0].normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

async function fetchBytes(url: string, timeoutMs = 12000): Promise<Uint8Array | null> {
  try {
    const res = await fetch(url, { headers: { 'User-Agent': UA }, signal: AbortSignal.timeout(timeoutMs) });
    if (!res.ok) return null;
    const type = res.headers.get('content-type') || '';
    if (!type.startsWith('image/')) return null;
    const b = new Uint8Array(await res.arrayBuffer());
    return b.length > 3000 ? b : null;
  } catch {
    return null;
  }
}

async function fetchText(url: string): Promise<string | null> {
  try {
    const res = await fetch(url, { headers: { 'User-Agent': UA }, signal: AbortSignal.timeout(12000) });
    return res.ok ? await res.text() : null;
  } catch {
    return null;
  }
}

// Sites Hachette (Livre de poche, Fayard…) : la page du livre se trouve avec
// le titre et l'ISBN, et sa balise og:image pointe vers media.hachette.fr.
// On n'accepte l'image que si son adresse contient bien l'ISBN.
async function hachetteCandidates(isbn: string, title: string): Promise<string[]> {
  const slug = slugify(title);
  if (!slug) return [];
  const pages = [
    `https://www.livredepoche.com/livre/${slug}-${isbn}`,
    `https://www.fayard.fr/livre/${slug}-${isbn}/`,
    `https://www.grasset.fr/livre/${slug}-${isbn}/`,
    `https://www.calmann-levy.fr/livre/${slug}-${isbn}/`,
    `https://www.editions-jclattes.fr/livre/${slug}-${isbn}/`,
    `https://www.editions-stock.fr/livre/${slug}-${isbn}/`,
  ];
  const found = await Promise.all(pages.map(async (p) => {
    const html = await fetchText(p);
    const m = html?.match(/og:image"[^>]*content="([^"]+)"/);
    const img = m?.[1]?.replace(/&amp;/g, '&');
    return img && img.includes(isbn) ? img.replace('fit-in/500x500', 'fit-in/800x800') : null;
  }));
  return found.filter((x): x is string => !!x);
}

async function googleCandidates(isbn: string): Promise<string[]> {
  // La recherche Google Books (volumes?q=) est souvent en panne ; l'ancienne
  // API « viewapi » donne l'identifiant du livre, puis volumes/{id} répond.
  const txt = await fetchText(`https://books.google.com/books?bibkeys=ISBN:${isbn}&jscmd=viewapi&callback=cb`);
  const id = txt?.match(/id=([A-Za-z0-9_-]+)/)?.[1];
  if (!id) return [];
  const vol = await fetchText(`https://www.googleapis.com/books/v1/volumes/${id}`);
  let links: Record<string, string> = {};
  try { links = JSON.parse(vol || '{}').volumeInfo?.imageLinks || {}; } catch { /* rien */ }
  const urls = ['extraLarge', 'large', 'medium', 'small', 'thumbnail'].map((k) => links[k]).filter(Boolean);
  urls.push(`https://books.google.com/books/content?id=${id}&printsec=frontcover&img=1&zoom=1`);
  return urls.map((u) => u.replace('http://', 'https://'));
}

function rgbaAt(img: Image, x: number, y: number): [number, number, number] {
  const i = (y * img.width + x) * 4;
  return [img.bitmap[i], img.bitmap[i + 1], img.bitmap[i + 2]];
}

// Une ligne (ou colonne) de bord est une « bande » si elle est d'une seule
// couleur sur toute sa partie centrale (fond blanc, cadre gris…). Les 10 %
// de chaque extrémité sont ignorés : une ligne de cadre croise le liseré des
// deux autres côtés (cas d'Une unique lueur, 26/10/2026).
// Renvoie la couleur de la bande, ou null si la ligne n'est pas unie.
function bandColor(img: Image, horizontal: boolean, pos: number, tol = 24): [number, number, number] | null {
  const len = horizontal ? img.width : img.height;
  const from = Math.floor(len * 0.1), to = Math.ceil(len * 0.9);
  const ref = horizontal ? rgbaAt(img, from, pos) : rgbaAt(img, pos, from);
  for (let k = from; k < to; k += 2) {
    const [r, g, b] = horizontal ? rgbaAt(img, k, pos) : rgbaAt(img, pos, k);
    if (Math.abs(r - ref[0]) > tol || Math.abs(g - ref[1]) > tol || Math.abs(b - ref[2]) > tol) return null;
  }
  return ref;
}

const sameColor = (a: number[], b: number[], tol = 30) => a.every((v, i) => Math.abs(v - b[i]) <= tol);

// Retire les bandes unies autour de la couverture. Prudence apprise le
// 26/10/2026 : sur une couverture à fond blanc (Folio, L'Harmattan), rogner le
// haut mange le titre. Donc :
// - image trop large (carrée avec bandes sur les côtés) : côtés seulement, et
//   tant que la bande garde la couleur du bord (une couverture jaune unie
//   derrière une bande blanche n'est pas une bande : Cahier d'un retour au
//   pays natal) ;
// - image trop haute : haut et bas seulement, même règle ;
// - format déjà proche du livre : seulement un cadre qui fait le tour complet
//   (les 4 côtés unis), au plus 8 % par côté ; ici la couleur peut changer
//   (liseré gris puis marge blanche).
function trimBands(img: Image): Image {
  const w = img.width, h = img.height, ratio = w / h;
  const count = (horizontal: boolean, fromEnd: boolean, max: number, keepColor: boolean) => {
    let n = 0, first: number[] | null = null;
    const last = (horizontal ? h : w) - 1;
    while (n < max) {
      const c = bandColor(img, horizontal, fromEnd ? last - n : n);
      if (!c || (keepColor && first && !sameColor(c, first))) break;
      first ??= c; n++;
    }
    return n;
  };
  let left = 0, right = 0, top = 0, bottom = 0;
  if (ratio > 0.72) {
    left = count(false, false, Math.floor(w * 0.3), true); right = count(false, true, Math.floor(w * 0.3), true);
  } else if (ratio < 0.6) {
    top = count(true, false, Math.floor(h * 0.25), true); bottom = count(true, true, Math.floor(h * 0.25), true);
  } else {
    const l = count(false, false, Math.floor(w * 0.08), false), r = count(false, true, Math.floor(w * 0.08), false);
    const t = count(true, false, Math.floor(h * 0.08), false), b = count(true, true, Math.floor(h * 0.08), false);
    if (Math.min(l, r, t, b) >= 2) { left = l; right = r; top = t; bottom = b; }
  }
  if (!left && !right && !top && !bottom) return img;
  return img.clone().crop(left, top, w - left - right, h - top - bottom);
}

// Format 2:3 plein cadre : légère mise à l'échelle si le rapport est proche
// (invisible), sinon recadrage centré.
function toBookFormat(img: Image): Image {
  const target = OUT_W / OUT_H;
  const ratio = img.width / img.height;
  if (Math.abs(ratio - target) <= 0.08) return img.clone().resize(OUT_W, OUT_H);
  if (ratio > target) {
    const cw = Math.round(img.height * target);
    return img.clone().crop(Math.round((img.width - cw) / 2), 0, cw, img.height).resize(OUT_W, OUT_H);
  }
  const ch = Math.round(img.width / target);
  return img.clone().crop(0, Math.round((img.height - ch) / 2), img.width, ch).resize(OUT_W, OUT_H);
}

function coverColor(img: Image): string {
  const small = img.clone().resize(32, Image.RESIZE_AUTO);
  let total = 0, n = 0;
  for (let i = 0; i < small.bitmap.length; i += 4) {
    const r = small.bitmap[i], g = small.bitmap[i + 1], b = small.bitmap[i + 2];
    total += Math.max(r, g, b) - Math.min(r, g, b); n++;
  }
  return n && total / n > 10 ? 'Couleur' : 'Noir et blanc';
}

async function decodeUsable(bytes: Uint8Array, url: string): Promise<Image | null> {
  try {
    const img = await Image.decode(bytes);
    if (!(img instanceof Image)) return null;
    if (img.width < 150 || img.height < 200) return null;
    if (url.includes('books.google.com') && GOOGLE_PLACEHOLDER_SIZES.has(`${img.width}x${img.height}`)) return null;
    const ratio = img.width / img.height;
    if (ratio > 1.2 || ratio < 0.4) return null; // capture d'écran, bandeau : pas une couverture
    return img;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, message: 'Méthode non supportée' }, 405);

  const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data: { user: caller }, error: authError } = await callerClient.auth.getUser();
  if (authError || !caller) return json({ ok: false, message: 'Non authentifié' }, 401);

  let body: { cover_url?: string; isbn?: string; title?: string; photo?: string; book_id?: number };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, message: 'Corps de requête invalide' }, 400);
  }
  const isbn = String(body.isbn || '').replace(/[^0-9X]/gi, '');
  const title = String(body.title || '');

  // Photo de couverture prise par un agent (27/10/2026) : déjà redressée et
  // améliorée dans le logiciel, elle est seulement vérifiée, remise au format
  // et rangée ici (dossier photos-a-verifier/). Les agents n'ont pas le droit d'écrire directement dans le
  // bucket book-covers (réservé au super-admin), d'où ce passage par le serveur.
  if (body.photo) {
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: profile } = await admin.from('profiles').select('role').eq('id', caller.id).maybeSingle();
    if (!['agent', 'super_admin'].includes(profile?.role)) return json({ ok: false, message: 'Réservé aux agents' }, 403);
    let img: Image;
    try {
      const decoded = await Image.decode(Uint8Array.from(atob(body.photo), (c) => c.charCodeAt(0)));
      if (!(decoded instanceof Image)) throw new Error('animation');
      img = decoded;
    } catch {
      return json({ ok: false, message: 'Photo illisible' }, 400);
    }
    if (img.width < 300 || img.height < 450) return json({ ok: false, message: 'Photo trop petite' }, 400);
    const final = toBookFormat(img);
    // Rangée dans photos-a-verifier/ : Mégane les contrôle depuis
    // superadmin.html (ou le tableau de bord Supabase) avant de les valider.
    // Le numéro du livre en tête du nom permet de retrouver sa fiche.
    const bookId = Number.isInteger(body.book_id) ? body.book_id : 0;
    const path = `photos-a-verifier/${bookId}-${slugify(title) || 'couverture'}-${Date.now()}.jpg`;
    const { error } = await admin.storage.from('book-covers').upload(path, await final.encodeJPEG(90), { contentType: 'image/jpeg' });
    if (error) return json({ ok: false, message: 'Envoi impossible : ' + error.message }, 500);
    const { data: pub } = admin.storage.from('book-covers').getPublicUrl(path);
    return json({ ok: true, cover_url: pub.publicUrl, color: coverColor(final), source: 'photo' });
  }

  // Ordre : éditeur d'abord (meilleure image, vraie face avant), puis l'image
  // proposée par l'API, puis Open Library et Google en lecture directe.
  const candidates: string[] = [];
  if (isbn.length === 13) {
    candidates.push(...await hachetteCandidates(isbn, title));
    candidates.push(...INTERFORUM_CODES.map((c) => `https://www.interforum.fr/images/${c}/P3/${isbn}.jpg`));
  }
  // input_checked : l'image proposée a bien été examinée (source autorisée).
  // Si elle est écartée et que rien d'autre n'est trouvé, le logiciel la
  // retire ; sinon il la garde telle quelle.
  let inputChecked = false;
  if (body.cover_url) {
    try {
      const u = new URL(body.cover_url);
      if (u.protocol === 'https:' && isAllowedHost(u.hostname)) { candidates.push(u.toString()); inputChecked = true; }
    } catch { /* adresse ignorée */ }
  }
  if (isbn) {
    candidates.push(`https://covers.openlibrary.org/b/isbn/${isbn}-L.jpg?default=false`);
    candidates.push(...await googleCandidates(isbn));
  }

  // Téléchargées en parallèle (la plupart des adresses éditeurs répondent 404
  // vite), puis examinées dans l'ordre de préférence.
  const urls = [...new Set(candidates)];
  const downloads = await Promise.all(urls.map((u) => fetchBytes(u)));
  for (const [i, url] of urls.entries()) {
    const bytes = downloads[i];
    if (!bytes) continue;
    const img = await decodeUsable(bytes, url);
    if (!img) continue;
    const final = toBookFormat(trimBands(img));
    const jpeg = await final.encodeJPEG(90);
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const path = `covers/${isbn || slugify(title) || 'couverture'}-${Date.now()}.jpg`;
    const { error } = await admin.storage.from('book-covers').upload(path, jpeg, { contentType: 'image/jpeg' });
    if (error) return json({ ok: false, message: 'Envoi impossible : ' + error.message }, 500);
    const { data: pub } = admin.storage.from('book-covers').getPublicUrl(path);
    return json({ ok: true, cover_url: pub.publicUrl, color: coverColor(final), source: new URL(url).hostname });
  }
  return json({ ok: false, input_checked: inputChecked, message: 'Aucune couverture exploitable trouvée' });
});
