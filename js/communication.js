// Écran Communication (05/11/2026) : prépare des posts Facebook et Instagram à partir
// de ce que la médiathèque fait déjà (coups de cœur, nouveautés, agenda).
// L'agent enregistre l'image, copie la légende et publie lui-même : aucun compte
// de réseau social n'est connecté à BliGO.
// Dessin en canvas 1080 x 1350. Une couverture non lisible est remplacée par une
// couverture dessinée avec le titre, pour que l'image reste toujours enregistrable.

export const LIEN = 'https://bligo.fr/telecharger.html';
const W = 1080, H = 1350;
const INK = '#083133', CREME = '#FFF6EA', MANGUE = '#FBA30F', ROSE = '#F0295D', GRIS = '#2B4B4D';
const JOURS = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];
const MOIS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
const MOIS_COURT = ['janv.', 'févr.', 'mars', 'avril', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const COULEURS = ['#F0295D', '#2F80ED', '#27AE60', '#7B4FD6', '#FA9509', '#123F3A'];

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// « de Val-Fleuri », « d'Anse-Bertrand », « des Abymes », « du Moule »
export function deCommune(nom) {
  const n = String(nom || '').trim();
  if (/^les\s/i.test(n)) return 'des ' + n.slice(4);
  if (/^le\s/i.test(n)) return 'du ' + n.slice(3);
  if (/^[aeiouyàâéèêîôûh]/i.test(n)) return "d'" + n;
  return 'de ' + n;
}

const heure = d => `${d.getHours()} h${d.getMinutes() ? ' ' + String(d.getMinutes()).padStart(2, '0') : ''}`;
function dateLongue(d) { return `${JOURS[d.getDay()]} ${d.getDate() === 1 ? '1er' : d.getDate()} ${MOIS[d.getMonth()]}`; }
function plage(ev) {
  const a = new Date(ev.event_date);
  if (!ev.duration_minutes) return `à ${heure(a)}`;
  const b = new Date(a.getTime() + ev.duration_minutes * 60000);
  return `de ${heure(a)} à ${heure(b)}`;
}

export function chargerImage(src) {
  return new Promise(res => {
    if (!src) return res(null);
    const i = new Image();
    i.crossOrigin = 'anonymous';
    const t = setTimeout(() => res(null), 8000); // image trop lente : couverture dessinée
    i.onload = () => { clearTimeout(t); res(i); };
    i.onerror = () => { clearTimeout(t); res(null); };
    i.src = src;
  });
}

export function degrade(c, x, y, w, h) {
  const g = c.createLinearGradient(x, y, x + w, y + h);
  g.addColorStop(0, '#FBA30F'); g.addColorStop(.55, '#F7691F'); g.addColorStop(1, '#F0295D');
  return g;
}
export function arrondi(c, x, y, w, h, r) { c.beginPath(); c.roundRect(x, y, w, h, r); }
export function lignes(c, texte, largeur) {
  const res = [];
  for (const para of String(texte).split('\n')) {
    let l = '';
    for (const m of para.split(' ')) {
      const t = l ? l + ' ' + m : m;
      if (c.measureText(t).width > largeur && l) { res.push(l); l = m; } else l = t;
    }
    res.push(l);
  }
  return res;
}
export function texte(c, t, x, y, { size, weight = 700, color = INK, font = 'Poppins', largeur = W - 2 * x, interligne = 1.05, max = 99, espace = 0 }) {
  c.fillStyle = color; c.textBaseline = 'top';
  c.font = `${weight} ${size}px ${font}, Arial, sans-serif`;
  if ('letterSpacing' in c) c.letterSpacing = espace ? `${espace}px` : '0px';
  let ls = lignes(c, t, largeur);
  if (ls.length > max) { ls = ls.slice(0, max); ls[max - 1] = ls[max - 1].replace(/\s*\S*$/, '') + '…'; }
  ls.forEach((l, i) => c.fillText(l, x, y + i * size * interligne));
  if ('letterSpacing' in c) c.letterSpacing = '0px';
  return y + ls.length * size * interligne;
}
// Hauteur qu'occuperait un texte, sans le dessiner.
function hauteur(c, t, { size, weight = 600, font = 'Poppins', largeur, interligne = 1.1, max = 99 }) {
  c.font = `${weight} ${size}px ${font}, Arial, sans-serif`;
  return Math.min(lignes(c, t, largeur).length, max) * size * interligne;
}
// Titre ramené à la taille qui tient sur `max` lignes.
export function tailleQuiTient(c, t, size, mini, largeur, max, weight = 700) {
  for (let s = size; s >= mini; s -= 4) {
    c.font = `${weight} ${s}px Poppins, Arial, sans-serif`;
    if (lignes(c, t, largeur).length <= max) return s;
  }
  return mini;
}
export function image(c, img, x, y, w, h, r) {
  c.save(); arrondi(c, x, y, w, h, r); c.clip();
  const k = Math.max(w / img.width, h / img.height), iw = img.width * k, ih = img.height * k;
  c.drawImage(img, x + (w - iw) / 2, y + (h - ih) / 2, iw, ih);
  c.restore();
}
// Refonte du 18/11/2026 (retour de Mégane : « grossier, pas très fin ») :
// titres moins gras et plus petits, beaucoup d'air, petites étiquettes en
// capitales espacées, couvertures avec une ombre douce, filet fin au pied.
// Chaque bloc de texte est placé d'après la hauteur réelle du précédent :
// plus rien ne se chevauche, même avec un titre long.
const FOND = '#FBF6EF', TRAIT = 'rgba(8,49,51,.14)';

function ombre(c, x, y, w, h, r, force = 1) {
  c.save();
  c.shadowColor = `rgba(8,49,51,${.30 * force})`; c.shadowBlur = 50; c.shadowOffsetY = 22;
  c.fillStyle = '#fff'; arrondi(c, x, y, w, h, r); c.fill();
  c.restore();
}
function couverture(c, livre, x, y, w, h, n = 0) {
  const r = Math.max(6, w * .02);
  ombre(c, x, y, w, h, r);
  if (livre._img) return image(c, livre._img, x, y, w, h, r);
  c.fillStyle = COULEURS[n % COULEURS.length]; arrondi(c, x, y, w, h, r); c.fill();
  const s = Math.round(w * .1);
  const fin = texte(c, livre.title, x + w * .1, y + w * .12, { size: s, weight: 600, color: '#fff', largeur: w * .8, interligne: 1.15, max: 6 });
  texte(c, livre.author || '', x + w * .1, Math.max(fin + s, y + h - w * .2), { size: Math.round(s * .55), weight: 500, font: 'Inter', color: '#fff', largeur: w * .8, max: 2 });
}
function etiquette(c, t, x, y, color) {
  return texte(c, t.toUpperCase(), x, y, { size: 22, weight: 600, font: 'Inter', color, espace: 4, largeur: W - x - M });
}
function entete(c, a, couleur) {
  let x = M;
  if (a.logo) {
    c.fillStyle = '#fff'; c.beginPath(); c.arc(M + 30, 72 + 30, 30, 0, Math.PI * 2); c.fill();
    const k = Math.min(46 / a.logo.width, 46 / a.logo.height), lw = a.logo.width * k, lh = a.logo.height * k;
    c.drawImage(a.logo, M + 30 - lw / 2, 102 - lh / 2, lw, lh);
    x = M + 76;
  }
  const t = `Médiathèque Municipale ${deCommune(a.nom)}`;
  c.font = `500 26px Inter, Arial, sans-serif`;
  const s = c.measureText(t).width > W - x - M ? 21 : 26;
  texte(c, t, x, 88, { size: s, weight: 500, font: 'Inter', color: couleur, largeur: W - x - M, max: 1 });
}
function pied(c, a, couleur, t, sombre = false) {
  c.fillStyle = sombre ? 'rgba(255,255,255,.18)' : TRAIT; c.fillRect(M, H - 150, W - 2 * M, 2);
  texte(c, t, M, H - 104, { size: 28, weight: 500, font: 'Inter', color: couleur, largeur: W - 2 * M - 200, max: 1 });
  if (a.bligo) {
    const k = Math.min(110 / a.bligo.width, 56 / a.bligo.height), lw = a.bligo.width * k, lh = a.bligo.height * k;
    if (sombre) { c.fillStyle = '#fff'; arrondi(c, W - M - lw - 24, H - 90 - lh / 2 - 12, lw + 24, lh + 24, 14); c.fill(); }
    c.drawImage(a.bligo, W - M - lw - (sombre ? 12 : 0), H - 90 - lh / 2, lw, lh);
  }
}

const M = 80;
const DESSIN = {
  coeur(c, a, d) {
    c.fillStyle = FOND; c.fillRect(0, 0, W, H);
    entete(c, a, GRIS);
    etiquette(c, 'Notre coup de cœur', M, 200, ROSE);
    // Couverture au centre, titre et auteur dessous.
    const titreH = hauteur(c, d.livre.title, { size: 46, largeur: W - 2 * M, max: 2 });
    const bas = H - 190 - titreH - 50;
    const h = Math.min(760, bas - 270), w = h / 1.5;
    couverture(c, d.livre, (W - w) / 2, 270, w, h);
    c.textAlign = 'center';
    const fin = texte(c, d.livre.title, W / 2, 270 + h + 56, { size: 46, weight: 600, largeur: W - 2 * M, interligne: 1.12, max: 2 });
    if (d.livre.author) texte(c, d.livre.author, W / 2, fin + 10, { size: 28, weight: 400, font: 'Inter', color: GRIS, largeur: W - 2 * M, max: 1 });
    c.textAlign = 'left';
    pied(c, a, GRIS, "À réserver sur l'appli BliGO");
  },
  nouveautes(c, a, d) {
    c.fillStyle = INK; c.fillRect(0, 0, W, H);
    entete(c, a, 'rgba(255,255,255,.8)');
    etiquette(c, 'Nouveautés', M, 200, MANGUE);
    texte(c, 'Du nouveau\nen rayon', M, 246, { size: 84, weight: 600, color: '#fff', interligne: 1.08 });
    const livres = d.livres.slice(0, 4), n = livres.length;
    // Une rangée, comme sur une étagère, légèrement décalée en hauteur.
    const g = n === 4 ? 26 : 40;
    const w = n === 4 ? 212 : n === 3 ? 270 : n === 2 ? 330 : 420, h = w * 1.5;
    const x0 = (W - n * w - (n - 1) * g) / 2, y0 = Math.round((480 + H - 190 - h) / 2);
    livres.forEach((l, i) => couverture(c, l, x0 + i * (w + g), y0 + (n > 2 ? (i % 2 ? 36 : -36) : 0), w, h, i));
    pied(c, a, 'rgba(255,255,255,.85)', "À réserver sur l'appli BliGO", true);
  },
  evenement(c, a, d) {
    const e = new Date(d.ev.event_date);
    c.fillStyle = FOND; c.fillRect(0, 0, W, H);
    entete(c, a, GRIS);
    etiquette(c, "À l'agenda", M, 200, ROSE);
    // Date en grand, sobre
    const jour = JOURS[e.getDay()];
    texte(c, String(e.getDate()), M, 250, { size: 190, weight: 600, color: ROSE, interligne: 1 });
    texte(c, `${jour[0].toUpperCase() + jour.slice(1)}\n${MOIS[e.getMonth()]} ${e.getFullYear()}`, M + (e.getDate() > 9 ? 250 : 140), 300, { size: 40, weight: 500, font: 'Inter', color: INK, interligne: 1.3, largeur: 600 });
    c.fillStyle = TRAIT; c.fillRect(M, 500, W - 2 * M, 2);
    // Titre : taille ajustée pour laisser la place aux infos
    const infos = [plage(d.ev)[0].toUpperCase() + plage(d.ev).slice(1), d.ev.location, d.ev.max_seats ? `${d.ev.max_seats} places, sur inscription` : 'Entrée libre'].filter(Boolean);
    const dispo = H - 190 - 560 - infos.length * 62 - 40;
    let s = 92;
    while (s > 52 && hauteur(c, d.ev.title, { size: s, largeur: W - 2 * M, interligne: 1.08 }) > dispo) s -= 4;
    // Bloc titre + infos centré dans l'espace libre, pour ne pas laisser un grand vide en bas.
    const bloc = hauteur(c, d.ev.title, { size: s, largeur: W - 2 * M, interligne: 1.08, max: 4 }) + 40 + infos.length * 62;
    const y0 = Math.max(556, Math.round(500 + (H - 190 - 500 - bloc) / 2));
    const fin = texte(c, d.ev.title, M, y0, { size: s, weight: 600, largeur: W - 2 * M, interligne: 1.08, max: 4 });
    let y = fin + 40;
    infos.forEach(t => {
      c.fillStyle = ROSE; c.beginPath(); c.arc(M + 8, y + 19, 7, 0, Math.PI * 2); c.fill();
      texte(c, t, M + 36, y, { size: 34, weight: 400, font: 'Inter', color: GRIS, largeur: W - 2 * M - 36, max: 1 });
      y += 62;
    });
    pied(c, a, GRIS, "Inscrivez-vous sur l'appli BliGO");
  },
  mois(c, a, d) {
    c.fillStyle = FOND; c.fillRect(0, 0, W, H);
    entete(c, a, GRIS);
    etiquette(c, 'Agenda', M, 200, ROSE);
    texte(c, 'Prochains\nrendez-vous', M, 246, { size: 84, weight: 600, interligne: 1.08 });
    let y = 480;
    const limite = H - 190;
    for (const ev of d.evs.slice(0, 5)) {
      const e = new Date(ev.event_date);
      const tH = hauteur(c, ev.title, { size: 36, largeur: W - 2 * M - 190, interligne: 1.15, max: 2 });
      const rowH = Math.max(110, tH + 52) + 44;
      if (y + rowH > limite) break;
      c.fillStyle = TRAIT; c.fillRect(M, y, W - 2 * M, 2);
      texte(c, String(e.getDate()), M, y + 26, { size: 64, weight: 600, color: ROSE, interligne: 1 });
      texte(c, MOIS_COURT[e.getMonth()].toUpperCase(), M + 2, y + 96, { size: 20, weight: 600, font: 'Inter', color: ROSE, espace: 3, largeur: 140 });
      const fin = texte(c, ev.title, M + 190, y + 30, { size: 36, weight: 600, largeur: W - 2 * M - 190, interligne: 1.15, max: 2 });
      texte(c, `${JOURS[e.getDay()][0].toUpperCase() + JOURS[e.getDay()].slice(1)}, ${plage(ev)}`, M + 190, fin + 10, { size: 26, weight: 400, font: 'Inter', color: GRIS, largeur: W - 2 * M - 190, max: 1 });
      y += rowH;
    }
    pied(c, a, GRIS, "Inscrivez-vous sur l'appli BliGO");
  },
  vacances(c, a) {
    const g = c.createLinearGradient(0, 0, W, H);
    g.addColorStop(0, '#FFE9C7'); g.addColorStop(1, '#FFD3DC');
    c.fillStyle = g; c.fillRect(0, 0, W, H);
    entete(c, a, GRIS);
    etiquette(c, 'Bientôt les vacances', M, 200, ROSE);
    const fin = texte(c, 'Votre pile\nde lecture\nest prête ?', M, 270, { size: 124, weight: 600, interligne: 1.05 });
    texte(c, 'Réservez vos livres depuis le canapé,\non vous prévient dès qu’ils sont prêts.', M, fin + 60, { size: 36, weight: 400, font: 'Inter', color: GRIS, interligne: 1.4, largeur: W - 2 * M });
    pied(c, a, GRIS, "Sur l'appli BliGO");
  },
  carte(c, a) {
    c.fillStyle = INK; c.fillRect(0, 0, W, H);
    entete(c, a, 'rgba(255,255,255,.8)');
    etiquette(c, 'Votre carte', M, 200, MANGUE);
    texte(c, 'Toujours\nsur vous.', M, 246, { size: 110, weight: 600, color: '#fff', interligne: 1.05 });
    const x = M, y = 600, w = W - 2 * M, h = 480;
    ombre(c, x, y, w, h, 40, 1.4);
    c.fillStyle = degrade(c, x, y, w, h); arrondi(c, x, y, w, h, 40); c.fill();
    c.save(); arrondi(c, x, y, w, h, 40); c.clip(); c.fillStyle = 'rgba(255,255,255,.12)'; c.beginPath(); c.arc(x + w - 60, y + 60, 170, 0, Math.PI * 2); c.fill(); c.restore();
    etiquette(c, 'Carte de médiathèque', x + 56, y + 56, 'rgba(255,255,255,.9)');
    texte(c, 'Dans votre\ntéléphone.', x + 56, y + 100, { size: 56, weight: 600, color: '#fff', interligne: 1.1, largeur: w - 112 });
    c.fillStyle = '#fff'; arrondi(c, x + w - 56 - 190, y + h - 56 - 190, 190, 190, 22); c.fill();
    const n = 7, t = 150 / n; c.fillStyle = INK;
    [1,1,1,0,1,1,1, 1,0,1,0,1,0,1, 1,1,1,0,1,1,1, 0,0,0,1,0,1,0, 1,0,1,0,1,1,0, 0,1,0,1,0,1,1, 1,1,0,1,1,0,1].forEach((v, i) => { if (v) c.fillRect(x + w - 56 - 170 + (i % n) * t, y + h - 56 - 170 + Math.floor(i / n) * t, t - 3, t - 3); });
    texte(c, 'À présenter au comptoir\npour emprunter vos livres.', x + 56, y + h - 56 - 90, { size: 30, weight: 500, font: 'Inter', color: '#fff', interligne: 1.35, largeur: w - 112 - 220 });
    pied(c, a, 'rgba(255,255,255,.85)', "Sur l'appli BliGO", true);
  },
};

// Légendes : {LIEN} est remplacé au moment de copier, selon le réseau.
const LEGENDE = {
  coeur: (a, d) => `❤️ Notre coup de cœur du moment : « ${d.livre.title} »${d.livre.author ? ', de ' + d.livre.author : ''}.\n\nEnvie de le découvrir ? Réservez-le sur l'appli BliGO, on vous prévient dès qu'il est prêt.\n\n{LIEN}`,
  nouveautes: a => `📚 Du nouveau en rayon à la Médiathèque Municipale ${deCommune(a.nom)} !\n\nLequel lirez-vous en premier ? Réservez-le sur l'appli BliGO.\n\n{LIEN}`,
  evenement: (a, d) => { const e = new Date(d.ev.event_date); return `✨ ${d.ev.title}, ${dateLongue(e)} ${plage(d.ev)}${d.ev.location ? ', ' + d.ev.location : ''}.\n\n${d.ev.max_seats ? d.ev.max_seats + ' places. ' : ''}Inscrivez-vous sur l'appli BliGO.\n\n{LIEN}`; },
  mois: (a, d) => `🗓️ À venir à ${a.nom} :\n${d.evs.slice(0, 4).map(ev => `• ${ev.title}, ${dateLongue(new Date(ev.event_date))}`).join('\n')}\n\nRetrouvez tout l'agenda et inscrivez-vous sur l'appli BliGO.\n\n{LIEN}`,
  vacances: () => `☀️ Les vacances approchent. Votre pile de lecture est prête ?\n\nRéservez vos livres sur l'appli BliGO, on vous prévient dès qu'ils sont prêts à retirer.\n\n{LIEN}`,
  carte: () => `💳 Plus besoin de chercher votre carte de médiathèque : elle est dans votre téléphone, avec l'appli BliGO.\n\n{LIEN}`,
};

let etat = null;

async function avecImage(livre) {
  if (livre._charge) return livre;
  livre._img = await chargerImage(livre.cover_url);
  livre._charge = true;
  return livre;
}

async function dessiner(p) {
  const cv = document.getElementById('com-cv-' + p.id);
  if (!cv) return;
  if (p.livre) await avecImage(p.livre);
  if (p.livres) await Promise.all(p.livres.slice(0, 4).map(avecImage));
  DESSIN[p.type](cv.getContext('2d'), etat.a, p);
  const ta = document.getElementById('com-cap-' + p.id);
  if (ta) ta.value = LEGENDE[p.type](etat.a, p);
}

function carte(p) {
  const choix = p.options
    ? `<select data-com-choix="${p.id}" class="w-full border border-mango-100 rounded-lg px-2.5 py-2 text-sm bg-white">${p.options.map((o, i) => `<option value="${i}">${esc(o.label)}</option>`).join('')}</select>`
    : '';
  return `<div class="bg-white border border-mango-100 rounded-xl p-4 shadow-sm" style="display:flex;flex-direction:column;gap:10px;min-width:0">
    <div><p class="text-sm font-bold text-ink">${esc(p.titre)}</p><p class="text-xs text-ink/55 mt-0.5">${esc(p.quand)}</p></div>
    <canvas id="com-cv-${p.id}" width="${W}" height="${H}" style="width:100%;height:auto;border-radius:10px;display:block"></canvas>
    ${choix}
    <textarea id="com-cap-${p.id}" aria-label="Légende" class="w-full border border-mango-100 rounded-lg px-2.5 py-2 text-sm bg-white" style="min-height:150px;resize:vertical"></textarea>
    <div style="display:flex;flex-wrap:wrap;gap:8px">
      <button type="button" data-com-img="${p.id}" class="bg-brand text-white rounded-lg px-3 py-2 text-sm font-semibold">Enregistrer l'image</button>
      <button type="button" data-com-copy="${p.id}" data-net="fb" class="border border-brand/20 text-ink bg-white rounded-lg px-3 py-2 text-sm font-semibold">Copier pour Facebook</button>
      <button type="button" data-com-copy="${p.id}" data-net="ig" class="border border-brand/20 text-ink bg-white rounded-lg px-3 py-2 text-sm font-semibold">Copier pour Instagram</button>
    </div>
    <p id="com-st-${p.id}" class="text-xs text-ink/60" aria-live="polite" style="min-height:16px"></p>
  </div>`;
}

export async function ouvrirCommunication({ supabase, communeId, telecharger }) {
  const root = document.getElementById('com-posts');
  if (!root) return;
  root.innerHTML = '<p class="text-sm text-ink/55">Préparation des posts…</p>';
  await Promise.race([
    Promise.all(['700 40px Poppins', '600 40px Poppins', '500 40px Inter', '600 40px Inter'].map(f => document.fonts.load(f))),
    new Promise(r => setTimeout(r, 4000)),
  ]).catch(() => {});

  const maintenant = new Date().toISOString();
  const [{ data: commune }, { data: coeurs }, { data: nouv }, { data: recents }, { data: evs }] = await Promise.all([
    supabase.from('communes').select('name, logo_url').eq('id', communeId).maybeSingle(),
    supabase.from('books').select('title, author, cover_url').eq('commune_id', communeId).eq('is_staff_pick', true).limit(8),
    supabase.from('books').select('title, author, cover_url').eq('commune_id', communeId).eq('is_new_release', true).not('cover_url', 'is', null).order('created_at', { ascending: false }).limit(4),
    supabase.from('books').select('title, author, cover_url').eq('commune_id', communeId).not('cover_url', 'is', null).order('created_at', { ascending: false }).limit(12),
    supabase.from('events').select('title, event_date, location, max_seats, duration_minutes').eq('commune_id', communeId).gte('event_date', maintenant).order('event_date').limit(8),
  ]);

  const [logo, bligo] = await Promise.all([chargerImage(commune?.logo_url), chargerImage('img/bligo-logo.png')]);
  etat = { a: { nom: commune?.name || '', logo, bligo } };

  // Nouveautés : jamais le même livre que le coup de cœur (retour du 18/11),
  // complétées par les derniers documents ajoutés pour avoir 4 couvertures.
  const vus = new Set((coeurs || []).slice(0, 1).map(l => l.title));
  const livresNouv = [];
  for (const l of [...(nouv || []), ...(recents || [])]) {
    if (livresNouv.length >= 4) break;
    if (vus.has(l.title)) continue;
    vus.add(l.title); livresNouv.push(l);
  }
  const posts = [];
  if (coeurs?.length) posts.push({ id: 'coeur', type: 'coeur', titre: 'Coup de cœur', quand: `${coeurs.length} coup${coeurs.length > 1 ? 's' : ''} de cœur dans ton catalogue`, livre: coeurs[0], options: coeurs.map(l => ({ label: l.title, val: l })) });
  if (livresNouv.length) posts.push({ id: 'nouveautes', type: 'nouveautes', titre: 'Nouveautés', quand: (nouv && nouv.length) ? 'Tes dernières nouveautés, sans ton coup de cœur' : 'Tes derniers documents ajoutés', livres: livresNouv });
  if (evs?.length) posts.push({ id: 'evenement', type: 'evenement', titre: 'Un événement', quand: `${evs.length} événement${evs.length > 1 ? 's' : ''} à venir dans ton agenda`, ev: evs[0], options: evs.map(e => ({ label: `${new Date(e.event_date).getDate()} ${MOIS[new Date(e.event_date).getMonth()]} : ${e.title}`, val: e })) });
  if (evs?.length > 1) posts.push({ id: 'mois', type: 'mois', titre: 'Les prochains rendez-vous', quand: 'Selon ton agenda', evs });
  posts.push({ id: 'vacances', type: 'vacances', titre: 'Vacances', quand: 'Avant chaque période de vacances' });
  posts.push({ id: 'carte', type: 'carte', titre: "Rappel de l'appli", quand: "À tout moment de l'année" });
  etat.posts = posts;

  root.innerHTML = `<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,300px),1fr));gap:16px">${posts.map(carte).join('')}</div>`;

  root.onchange = e => {
    const id = e.target.dataset?.comChoix; if (!id) return;
    const p = posts.find(x => x.id === id), v = p.options[+e.target.value].val;
    if (p.type === 'coeur') p.livre = v; else p.ev = v;
    dessiner(p);
  };
  root.onclick = async e => {
    const b = e.target.closest('button'); if (!b) return;
    const idImg = b.dataset.comImg, idCopie = b.dataset.comCopy;
    if (idImg) {
      const st = document.getElementById('com-st-' + idImg);
      try {
        const blob = await new Promise((res, rej) => document.getElementById('com-cv-' + idImg).toBlob(x => x ? res(x) : rej(new Error('image')), 'image/png'));
        telecharger(blob, `post-${idImg}-bligo.png`);
        st.textContent = 'Image enregistrée.';
      } catch (err) { st.textContent = "L'image n'a pas pu être enregistrée."; }
    }
    if (idCopie) {
      const st = document.getElementById('com-st-' + idCopie);
      const lien = b.dataset.net === 'fb' ? `👉 ${LIEN}` : '👉 Le lien est dans notre bio !';
      const t = document.getElementById('com-cap-' + idCopie).value.replace('{LIEN}', lien);
      try { await navigator.clipboard.writeText(t); st.textContent = b.dataset.net === 'fb' ? 'Légende Facebook copiée.' : 'Légende Instagram copiée. Pense à mettre le lien dans la bio ou en story.'; }
      catch (err) { st.textContent = 'Copie impossible : sélectionne le texte à la main.'; }
    }
  };
  await Promise.all(posts.map(dessiner));
  return posts;
}
