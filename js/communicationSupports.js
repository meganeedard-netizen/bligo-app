// Supports de lancement de l'écran Communication (05/11/2026) : affiche, flyer, post,
// mail et texte pour le bulletin, au nom et au logo de la médiathèque.
// Dessinés en canvas (300 dpi pour l'imprimé), PDF écrit sans bibliothèque.
import { LIEN, deCommune, chargerImage, degrade, arrondi, texte, tailleQuiTient } from './communication.js?v=20261105b';

const INK = '#083133', GRIS = '#2B4B4D', ROSE = '#F0295D';
const K = 300 / 72;
const PHRASE_DONS = "Des livres à donner ? Apportez-les à la médiathèque, elle vous dira s'ils peuvent rejoindre ses collections.";
const JOURS = ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
const MOIS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function dessinerIcone(c, type, x, y, s, couleur) {
  const chemins = {
    res: 'M4 5.5C7 4 10 4.3 12 6c2-1.7 5-2 8-.5V19c-3-1.5-6-1.2-8 .5-2-1.7-5-2-8-.5ZM12 6v13.5',
    evt: 'M6.5 5h11a3 3 0 0 1 3 3v9.5a3 3 0 0 1-3 3h-11a3 3 0 0 1-3-3V8a3 3 0 0 1 3-3ZM3.5 10h17M8 3v4M16 3v4M9 15l2 2 4-4',
    car: 'M5.5 5h13a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3h-13a3 3 0 0 1-3-3V8a3 3 0 0 1 3-3ZM6.3 9h3.4a.8.8 0 0 1 .8.8v3.4a.8.8 0 0 1-.8.8H6.3a.8.8 0 0 1-.8-.8V9.8a.8.8 0 0 1 .8-.8ZM13.5 9.5h5M13.5 13h5M5.5 16.5h13',
  };
  c.save(); c.translate(x, y); c.scale(s / 24, s / 24);
  c.strokeStyle = couleur; c.lineWidth = 1.6; c.lineCap = 'round'; c.lineJoin = 'round';
  c.stroke(new Path2D(chemins[type])); c.restore();
}

function ecranCatalogue(c, a, x, y, w) {
  const u = w / 507;
  c.drawImage(a.accueil, x, y, w, a.accueil.height * u);
  c.fillStyle = '#fff'; c.fillRect(x, y + 20 * u, 365 * u, 90 * u);
  if (a.logo) { const k = Math.min(62 * u / a.logo.width, 62 * u / a.logo.height); c.drawImage(a.logo, x + 55 * u - a.logo.width * k / 2, y + 62 * u - a.logo.height * k / 2, a.logo.width * k, a.logo.height * k); }
  texte(c, 'Bonjour Camille', x + 100 * u, y + 28 * u, { size: 24 * u, largeur: 265 * u, max: 1 });
  texte(c, `Médiathèque ${deCommune(a.nom)}`, x + 100 * u, y + 60 * u, { size: 15 * u, weight: 600, font: 'Inter', color: '#6F8A8C', largeur: 265 * u, max: 1 });
  texte(c, 'Horaires', x + 100 * u, y + 83 * u, { size: 14 * u, weight: 600, font: 'Inter', color: '#C8620A', largeur: 200 * u, max: 1 });
}
function ecranAgenda(c, a, x, y, w) {
  const u = w / 507, H = w * 2.2;
  c.fillStyle = '#fff'; c.fillRect(x, y, w, H);
  c.textAlign = 'center';
  texte(c, 'Agenda culturel', x + w / 2, y + 16 * u, { size: 22 * u, color: '#5F7C7E', largeur: w });
  c.textAlign = 'left';
  c.fillStyle = '#EEEEF1'; arrondi(c, x + 24 * u, y + 84 * u, 459 * u, 52 * u, 14 * u); c.fill();
  c.fillStyle = '#fff'; arrondi(c, x + 29 * u, y + 90 * u, 222 * u, 40 * u, 10 * u); c.fill();
  texte(c, 'À venir', x + 112 * u, y + 100 * u, { size: 17 * u, largeur: 150 * u, weight: 600 });
  texte(c, 'Historique', x + 325 * u, y + 100 * u, { size: 17 * u, largeur: 150 * u, weight: 600, color: '#7D9193' });
  let top = y + 170 * u;
  a.evenements.slice(0, 4).forEach(ev => {
    const d = new Date(ev.event_date), bx = x + 24 * u;
    c.fillStyle = degrade(c, bx + 18 * u, top + 8 * u, 56 * u, 56 * u); arrondi(c, bx + 18 * u, top + 8 * u, 56 * u, 56 * u, 14 * u); c.fill();
    dessinerIcone(c, 'evt', bx + 30 * u, top + 20 * u, 32 * u, '#fff');
    const fin = texte(c, ev.title, x + 118 * u, top + 8 * u, { size: 20 * u, largeur: 350 * u, interligne: 1.15, max: 2 });
    const f2 = texte(c, `${JOURS[d.getDay()]} ${d.getDate()} ${MOIS[d.getMonth()]} à ${d.getHours()} h${d.getMinutes() ? String(d.getMinutes()).padStart(2, '0') : ''}`, x + 118 * u, fin + 4 * u, { size: 15 * u, weight: 700, font: 'Inter', color: '#A91E55', largeur: 350 * u, max: 1 });
    const f3 = texte(c, ev.location || `Médiathèque ${deCommune(a.nom)}`, x + 118 * u, f2 + 6 * u, { size: 14 * u, weight: 500, font: 'Inter', color: '#7D9193', largeur: 350 * u, max: 1 });
    c.fillStyle = '#FF9B2F'; arrondi(c, x + 118 * u, f3 + 14 * u, 214 * u, 44 * u, 14 * u); c.fill();
    texte(c, "Je souhaite m'inscrire", x + 138 * u, f3 + 25 * u, { size: 17 * u, weight: 700, font: 'Inter', color: '#fff', largeur: 190 * u, max: 1 });
    top = f3 + 92 * u;
  });
}
function telephone(c, a, x, y, w, dessin) {
  const h = w * 2.06, b = w * .032;
  c.fillStyle = '#0d0d0f'; arrondi(c, x, y, w, h, w * .14); c.fill();
  c.save(); arrondi(c, x + b, y + b, w - 2 * b, h - 2 * b, w * .11); c.clip();
  c.fillStyle = '#fff'; c.fillRect(x + b, y + b, w - 2 * b, h - 2 * b);
  dessin(c, a, x + b, y + b, w - 2 * b);
  c.restore();
}
function bandeau(c, a, largeur, hauteur, l1, l2, top, w, eco) {
  c.save(); c.beginPath(); c.rect(0, 0, largeur, hauteur); c.clip();
  c.fillStyle = eco ? '#FFF6EA' : degrade(c, 0, 0, largeur, hauteur); c.fillRect(0, 0, largeur, hauteur);
  telephone(c, a, l1, top, w, ecranCatalogue);
  telephone(c, a, l2, top, w, ecranAgenda);
  c.restore();
}
function tete(c, a, x, y, d, f1, f2, largeur) {
  if (a.logo) {
    c.fillStyle = '#fff'; c.beginPath(); c.arc(x + d / 2, y + d / 2, d / 2, 0, Math.PI * 2); c.fill();
    const k = Math.min(d * .82 / a.logo.width, d * .82 / a.logo.height);
    c.drawImage(a.logo, x + d / 2 - a.logo.width * k / 2, y + d / 2 - a.logo.height * k / 2, a.logo.width * k, a.logo.height * k);
  }
  const tx = a.logo ? x + d + d * .2 : x, dispo = largeur - tx - x;
  texte(c, 'Médiathèque Municipale', tx, y + d * .14, { size: f1, weight: 600, largeur: dispo, max: 1 });
  const s = tailleQuiTient(c, deCommune(a.nom), f2, f2 * .5, dispo, 1);
  texte(c, deCommune(a.nom), tx, y + d * .14 + f1 * 1.2, { size: s, largeur: dispo, max: 1 });
}
function titre(c, x, y, fs, sub, ysub) {
  c.save();
  try { c.letterSpacing = `${-fs / 30}px`; } catch (e) { /* ancien navigateur */ }
  texte(c, 'Réservez depuis\nle canapé.', x, y, { size: fs, largeur: 2000, interligne: 1.03 });
  c.restore();
  c.font = `700 ${sub}px Poppins, Arial, sans-serif`;
  const t = 'Vos livres et vos sorties culturelles.', lg = c.measureText(t).width, g = c.createLinearGradient(x, 0, x + lg, 0);
  g.addColorStop(0, '#FA9509'); g.addColorStop(.5, '#F7591F'); g.addColorStop(1, ROSE);
  c.fillStyle = g; c.textBaseline = 'top'; c.fillText(t, x, ysub);
}
const AVANTAGES = [['res', 'Réservez', "Retirez vos livres dès qu'ils sont prêts."], ['evt', 'Inscrivez-vous', 'aux événements de votre commune.'], ['car', 'Votre carte', 'de médiathèque dans votre poche.']];
function avantages(c, x, y, largeur, ic, f1, f2) {
  const g = 16, w = (largeur - 2 * g) / 3;
  AVANTAGES.forEach(([k, t, s], i) => {
    const ax = x + i * (w + g);
    dessinerIcone(c, k, ax, y, ic, ROSE);
    const fin = texte(c, t, ax, y + ic + ic * .1, { size: f1, largeur: w + 8, max: 1 });
    texte(c, s, ax, fin + 2, { size: f2, weight: 500, font: 'Inter', color: GRIS, largeur: w, interligne: 1.25, max: 3 });
  });
}
function codeQr(c, a, x, y, s, pad) {
  c.fillStyle = '#fff'; arrondi(c, x, y, s, s, s * .09); c.fill();
  const i = s - 2 * pad, prec = c.imageSmoothingEnabled;
  c.imageSmoothingEnabled = false; c.drawImage(a.qr, x + pad, y + pad, i, i); c.imageSmoothingEnabled = prec;
  const t = i * .25, o = (i - t) / 2;
  c.fillStyle = '#fff'; arrondi(c, x + pad + o, y + pad + o, t, t, t * .18); c.fill();
  if (a.bligo) { const k = Math.min(t * .84 / a.bligo.width, t * .84 / a.bligo.height); c.drawImage(a.bligo, x + pad + i / 2 - a.bligo.width * k / 2, y + pad + i / 2 - a.bligo.height * k / 2, a.bligo.width * k, a.bligo.height * k); }
}
function magasins(c, a, x, y, h) {
  const w1 = a.apple.width * h / a.apple.height, w2 = a.google.width * h / a.google.height;
  c.drawImage(a.apple, x, y, w1, h); c.drawImage(a.google, x + w1 + h * .23, y, w2, h);
}
function bas(c, a, largeur, t, h, qs, qp, ql, f, fl, st, eco) {
  c.fillStyle = eco ? '#fff' : INK; c.fillRect(0, t, largeur, h);
  if (eco) { c.fillStyle = INK; c.fillRect(ql, t, largeur - 2 * ql, 1.5); }
  const y = t + (h - qs) / 2, x = ql + qs + ql * .7, col = eco ? INK : '#fff';
  codeQr(c, a, ql, y, qs, qp);
  texte(c, 'Votre médiathèque,\npartout avec vous !', x, y, { size: f, color: col, largeur: 2000, interligne: 1.08 });
  texte(c, "Scannez pour télécharger BliGO, l'appli culturelle gratuite.", x, y + f * 2.3, { size: fl, weight: 600, font: 'Inter', color: col, largeur: largeur - x - 8, max: 1 });
  magasins(c, a, x, y + qs - st, st);
}
const FORMATS = {
  affiche: { nom: 'Affiche A4', w: 595.28, h: 841.89, k: K, pages: 1, dessin(c, a) {
    bandeau(c, a, 595.28, 408, 78, 305, 86, 212, false); tete(c, a, 26, 15, 56, 13, 20, 595);
    this.corps(c, a, false);
  }, corps(c, a, eco) {
    c.fillStyle = '#fff'; c.fillRect(0, 408, 595.28, 272);
    titre(c, 30, 418, 54, 25, 533);
    avantages(c, 32, 568, 540, 26, 16.5, 12);
    if (a.dons) texte(c, 'Des livres à donner ? Apportez-les à la médiathèque.', 32, 660, { size: 10.5, weight: 600, font: 'Inter', color: GRIS, largeur: 530, max: 1 });
    bas(c, a, 595.28, 680, 161.89, 128, 10, 30, 25, 11.5, 35, eco);
  } },
  affiche_eco: { nom: 'Affiche A4 économe en encre', w: 595.28, h: 841.89, k: K, pages: 1, dessin(c, a) {
    bandeau(c, a, 595.28, 408, 78, 305, 86, 212, true); tete(c, a, 26, 15, 56, 13, 20, 595);
    FORMATS.affiche.corps(c, a, true);
  } },
  flyer: { nom: 'Flyer A5 recto-verso', w: 419.53, h: 595.28, k: K, pages: 2, dessin(c, a, page) {
    c.fillStyle = '#fff'; c.fillRect(0, 0, 419.53, 595.28);
    if (page === 0) {
      bandeau(c, a, 419.53, 298, 52, 218, 64, 150, false); tete(c, a, 18, 12, 44, 10, 15, 419);
      titre(c, 20, 306, 37, 18, 386);
      avantages(c, 21, 412, 385, 18, 11.5, 8.8);
      bas(c, a, 419.53, 490, 105.28, 86, 7, 20, 17, 7.4, 22, false);
      return;
    }
    c.fillStyle = degrade(c, 0, 0, 419.53, 72); c.fillRect(0, 0, 419.53, 72); tete(c, a, 18, 12, 44, 10, 15, 419);
    texte(c, 'Comment ça marche ?', 21, 84, { size: 27, largeur: 380 });
    const et = [['Téléchargez BliGO', "Scannez le QR code ou cherchez « BliGO » sur l'App Store ou Google Play."], ['Choisissez votre médiathèque', 'Sélectionnez la vôtre dans la liste.'], ['Créez votre compte', 'Prénom, nom, e-mail et mot de passe, puis le code à 6 chiffres reçu par e-mail.'], ['Nouvel adhérent ? Passez nous voir', "Avec une pièce d'identité et un justificatif de domicile : votre inscription est validée et votre carte s'active."]];
    let y = 124;
    et.forEach(([t, s], i) => {
      c.fillStyle = degrade(c, 21, y, 28, 28); c.beginPath(); c.arc(35, y + 14, 14, 0, Math.PI * 2); c.fill();
      c.textAlign = 'center'; texte(c, String(i + 1), 35, y + 5, { size: 14, color: '#fff', largeur: 30 }); c.textAlign = 'left';
      const f = texte(c, t, 60, y, { size: 14, largeur: 340, max: 1 });
      y = Math.max(texte(c, s, 60, f + 2, { size: 10, weight: 500, font: 'Inter', color: GRIS, largeur: 340, interligne: 1.3 }), y + 28) + 9;
    });
    const blocs = [["Déjà adhérent ?", "Créez votre compte avec l'e-mail connu de la médiathèque : vous réservez directement, sans justificatif."]];
    if (a.dons) blocs.push(['Des livres à donner ?', "Apportez-les à la médiathèque, elle vous dira s'ils peuvent rejoindre ses collections."]);
    blocs.forEach(([t, s]) => {
      c.fillStyle = '#FFF1DF'; arrondi(c, 21, y, 377.5, 44, 9); c.fill();
      const f0 = texte(c, t, 31, y + 5, { size: 9.5, largeur: 355 });
      texte(c, s, 31, f0 + 1, { size: 9.5, weight: 500, font: 'Inter', color: INK, largeur: 358, interligne: 1.2, max: 2 });
      y += 48;
    });
    c.fillStyle = INK; c.fillRect(0, 462, 419.53, 133.28);
    codeQr(c, a, 21, 473, 110, 9);
    const f = texte(c, 'Médiathèque Municipale', 148, 476, { size: 12, color: '#fff', largeur: 255, max: 1 });
    const f2 = texte(c, deCommune(a.nom), 148, f, { size: 12, color: '#fff', largeur: 255, max: 1 });
    texte(c, a.adresse || '', 148, f2 + 5, { size: 9.5, weight: 500, font: 'Inter', color: '#fff', largeur: 255, max: 2, interligne: 1.3 });
    magasins(c, a, 148, 552, 23);
    texte(c, 'Ne pas jeter sur la voie publique.', 21, 585, { size: 6, weight: 500, font: 'Inter', color: '#C9D6D6', largeur: 200 });
  } },
  post_1350: { nom: 'Post portrait 1080 × 1350', w: 810, h: 1012.5, k: 4 / 3, image: true, pages: 1, dessin(c, a) {
    c.fillStyle = '#fff'; c.fillRect(0, 0, 810, 1012.5);
    bandeau(c, a, 810, 520, 97, 428, 112, 285, false); tete(c, a, 28, 16, 78, 18, 26, 810);
    titre(c, 30, 530, 72, 33, 688);
    const l = [['res', 'Réservez', 32], ['evt', 'Inscrivez-vous', 300], ['car', 'Votre carte', 610]];
    l.forEach(([k, t, x]) => { dessinerIcone(c, k, x, 738, 24, ROSE); texte(c, t, x + 32, 739, { size: 18.5, largeur: 240, max: 1 }); });
    bas(c, a, 810, 790, 222.5, 186, 14, 32, 33, 12.5, 42, false);
  } },
  post_1080: { nom: 'Post carré 1080 × 1080', w: 810, h: 810, k: 4 / 3, image: true, pages: 1, dessin(c, a) {
    c.fillStyle = '#fff'; c.fillRect(0, 0, 810, 810);
    bandeau(c, a, 810, 380, 165, 420, 92, 225, false); tete(c, a, 24, 12, 68, 16, 23, 810);
    titre(c, 26, 390, 56, 27, 510);
    bas(c, a, 810, 556, 254, 212, 16, 28, 38, 14.5, 47, false);
  } },
};

async function rendre(cle, a, page = 0) {
  const f = FORMATS[cle], cv = document.createElement('canvas');
  cv.width = Math.round(f.w * f.k); cv.height = Math.round(f.h * f.k);
  const c = cv.getContext('2d'); c.scale(f.k, f.k);
  f.dessin(c, a, page);
  return cv;
}
const versBlob = (cv, type, q) => new Promise((res, rej) => cv.toBlob(b => b ? res(b) : rej(new Error('image')), type, q));

// PDF minimal : une image JPEG par page.
export async function jpegsVersPdf(jpegs, wPt, hPt, wPx, hPx) {
  const enc = new TextEncoder(), parts = [], xref = []; let pos = 0;
  const pousser = d => { const b = typeof d === 'string' ? enc.encode(d) : d; parts.push(b); pos += b.length; };
  const obj = (n, corps) => { xref[n] = pos; pousser(`${n} 0 obj\n${corps}\nendobj\n`); };
  pousser('%PDF-1.4\n%\xFF\xFF\xFF\xFF\n');
  const n = jpegs.length, kids = jpegs.map((_, i) => `${3 + i * 3} 0 R`).join(' ');
  obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
  obj(2, `<< /Type /Pages /Kids [${kids}] /Count ${n} >>`);
  for (let i = 0; i < n; i++) {
    const p = 3 + i * 3, im = p + 1, co = p + 2, flux = `q ${wPt} 0 0 ${hPt} 0 0 cm /I Do Q`;
    obj(p, `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${wPt} ${hPt}] /Resources << /XObject << /I ${im} 0 R >> >> /Contents ${co} 0 R >>`);
    xref[im] = pos;
    pousser(`${im} 0 obj\n<< /Type /XObject /Subtype /Image /Width ${wPx} /Height ${hPx} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpegs[i].length} >>\nstream\n`);
    pousser(jpegs[i]); pousser('\nendstream\nendobj\n');
    obj(co, `<< /Length ${flux.length} >>\nstream\n${flux}\nendstream`);
  }
  const debut = pos, total = 2 + n * 3;
  let table = `xref\n0 ${total + 1}\n0000000000 65535 f \n`;
  for (let i = 1; i <= total; i++) table += `${String(xref[i]).padStart(10, '0')} 00000 n \n`;
  pousser(`${table}trailer\n<< /Size ${total + 1} /Root 1 0 R >>\nstartxref\n${debut}\n%%EOF\n`);
  return new Blob(parts, { type: 'application/pdf' });
}
export async function creerPdf(cle, a) {
  const f = FORMATS[cle], jpegs = []; let cv;
  for (let p = 0; p < f.pages; p++) { cv = await rendre(cle, a, p); jpegs.push(new Uint8Array(await (await versBlob(cv, 'image/jpeg', .92)).arrayBuffer())); }
  return jpegsVersPdf(jpegs, f.w, f.h, cv.width, cv.height);
}

function b64(blob) { return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result).split(',')[1]); r.onerror = rej; r.readAsDataURL(blob); }); }
// Téléphone : feuille de partage (WhatsApp, mail…). Ordinateur : téléchargement.
async function partager(blob, nom, telecharger, st) {
  const natif = window.Capacitor?.Plugins?.BligoPartage;
  if (natif && blob.type.startsWith('image/')) { await natif.share({ title: nom, image: await b64(blob), fileName: nom }); return; }
  const fichier = new File([blob], nom, { type: blob.type });
  if (navigator.canShare?.({ files: [fichier] })) { try { await navigator.share({ files: [fichier] }); } catch (e) { /* annulé */ } return; }
  telecharger(blob, nom);
  st.textContent = 'Fichier enregistré : ajoute-le à ton message WhatsApp ou à ton e-mail.';
}
function imprimerImages(urls, wmm, hmm) {
  const fr = document.createElement('iframe');
  fr.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0';
  document.body.appendChild(fr);
  const d = fr.contentDocument;
  d.open(); d.write(`<!doctype html><style>@page{size:${wmm}mm ${hmm}mm;margin:0}html,body{margin:0}img{display:block;width:${wmm}mm;height:${hmm}mm;break-after:page}img:last-child{break-after:auto}</style>${urls.map(u => `<img src="${u}">`).join('')}`); d.close();
  const imgs = [...d.images];
  Promise.all(imgs.map(i => i.complete ? null : new Promise(r => { i.onload = r; i.onerror = r; }))).then(() => {
    fr.contentWindow.focus(); fr.contentWindow.print();
    setTimeout(() => fr.remove(), 60000);
  });
}

export function legendePost(a, reseau) {
  const fin = reseau === 'fb' ? `👉 Téléchargez l'appli ici : ${LIEN}` : '👉 Le lien de téléchargement est dans notre bio !';
  return `📚 Réservez depuis le canapé !\n\nAvec BliGO, l'appli culturelle gratuite de la Médiathèque Municipale ${deCommune(a.nom)}, vous pouvez :\n\n✅ réserver vos livres et autres documents : on vous prévient dès qu'ils sont prêts à retirer\n✅ vous inscrire aux événements culturels de la commune\n✅ avoir votre carte de médiathèque dématérialisée, toujours dans votre poche\n${a.dons ? `\n📦 ${PHRASE_DONS}\n` : ''}\n${fin}\n\nÀ très bientôt à la médiathèque !`;
}
export function texteBulletin(a) {
  return `Réservez depuis le canapé !\n\nLa Médiathèque Municipale ${deCommune(a.nom)} vous propose BliGO, une appli culturelle gratuite. Réservez vos livres et autres documents, puis retirez-les à la médiathèque dès qu'ils sont prêts. Découvrez les événements culturels de la commune et inscrivez-vous en quelques secondes. Votre carte de médiathèque reste aussi toujours dans votre poche.\n\nDéjà adhérent ? Créez votre compte avec l'e-mail connu de la médiathèque et réservez directement, sans justificatif.${a.dons ? `\n\n${PHRASE_DONS}` : ''}\n\nBliGO se télécharge gratuitement sur l'App Store et Google Play : ${LIEN}`;
}
export function mailHtml(a) {
  const nom = `Médiathèque Municipale ${deCommune(a.nom)}`;
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Réservez depuis le canapé</title></head><body style="margin:0;padding:0;background:#F3EEE6"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F3EEE6"><tr><td align="center" style="padding:24px 12px"><table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:100%;max-width:600px;background:#ffffff;border-radius:14px;font-family:Arial,Helvetica,sans-serif;color:#083133">
<tr><td style="padding:18px 28px">${a.logoUrl ? `<img src="${esc(a.logoUrl)}" width="56" alt="" style="display:block;margin-bottom:8px">` : ''}<b style="font-size:18px">${esc(nom)}</b></td></tr>
<tr><td style="padding:10px 30px 6px;font:16px/1.55 Arial,sans-serif"><h1 style="margin:0 0 4px;font:bold 31px/1.12 Arial,sans-serif;color:#083133">Réservez depuis le canapé.</h1><p style="margin:0 0 18px;font:bold 18px/1.3 Arial,sans-serif;color:#F0295D">Vos livres et vos sorties culturelles.</p>
<p style="margin:0 0 14px">Bonjour,</p><p style="margin:0 0 12px">Bonne nouvelle ! Avec <b>BliGO</b>, l'appli culturelle gratuite de votre Médiathèque Municipale, vous pouvez :</p>
<ul style="margin:0 0 16px;padding-left:22px"><li style="margin-bottom:6px">réserver vos livres et autres documents : on vous prévient dès qu'ils sont prêts à retirer ;</li><li style="margin-bottom:6px">vous inscrire aux événements culturels de votre commune ;</li><li>avoir votre carte de médiathèque dématérialisée, toujours dans votre poche.</li></ul>
<p style="margin:0 0 16px">Téléchargez l'appli, choisissez votre médiathèque et créez votre compte. Passez ensuite nous voir avec une pièce d'identité et un justificatif de domicile pour valider votre inscription.</p>
<p style="margin:0 0 22px;background:#FFF1DF;border-radius:8px;padding:12px 14px"><b>Déjà adhérent ?</b> Créez votre compte avec l'adresse e-mail connue de la médiathèque : vous réservez directement, sans justificatif à rapporter.</p>
${a.dons ? `<p style="margin:0 0 22px">${esc(PHRASE_DONS)}</p>` : ''}
<table role="presentation" align="center" cellpadding="0" cellspacing="0" style="margin:0 auto 24px"><tr><td style="background:#F0295D;border-radius:10px;padding:14px 30px"><a href="${LIEN}" style="font:bold 17px Arial,sans-serif;color:#ffffff;text-decoration:none">Télécharger BliGO</a></td></tr></table>
<p style="margin:0 0 4px">À très bientôt,</p><p style="margin:0 0 22px"><b>L'équipe de la ${esc(nom)}</b></p></td></tr>
<tr><td style="background:#FFF8EE;padding:14px 30px;font:12px/1.45 Arial,sans-serif;color:#5a7375">${esc(a.adresse || '')}<br>Vous recevez ce message car vous êtes inscrit(e) à la liste de diffusion de la commune. <a href="#" style="color:#5a7375">Se désinscrire</a></td></tr></table></td></tr></table></body></html>`;
}

export async function preparerDonnees({ supabase, communeId }) {
  const { default: QRCode } = await import('./vendor/qrcode.js?v=1.5.4');
  const [{ data: commune }, { data: evs }] = await Promise.all([
    supabase.from('communes').select('*').eq('id', communeId).maybeSingle(),
    supabase.from('events').select('title, event_date, location').eq('commune_id', communeId).gte('event_date', new Date().toISOString()).order('event_date').limit(4),
  ]);
  const [logo, bligo, accueil, apple, google] = await Promise.all([chargerImage(commune?.logo_url), chargerImage('img/bligo-logo.png'), chargerImage('img/kit/accueil.png'), chargerImage('img/kit/appstore.png'), chargerImage('img/kit/googleplay.png')]);
  const qr = document.createElement('canvas');
  await QRCode.toCanvas(qr, LIEN, { width: 900, margin: 0, errorCorrectionLevel: 'Q', color: { dark: INK, light: '#FFFFFF' } });
  // Écran d'exemple : les vrais événements, complétés par des exemples à des dates à venir.
  const exemples = [['Heure du conte', 7, 15], ["Atelier d'écriture", 12, 10], ['Exposition', 19, 10], ['Club de lecture', 26, 17]].map(([title, j, h]) => { const d = new Date(); d.setDate(d.getDate() + j); d.setHours(h, 0, 0, 0); return { title, event_date: d.toISOString(), location: '' }; });
  return { nom: commune?.name || '', adresse: commune?.address || '', logoUrl: commune?.logo_url || '', dons: commune?.donations_enabled === true, logo, bligo, accueil, apple, google, qr, evenements: [...(evs || []), ...exemples].slice(0, 4) };
}

export async function ouvrirSupports({ supabase, communeId, telecharger }) {
  const root = document.getElementById('com-supports');
  if (!root) return;
  root.innerHTML = '<p class="text-sm text-ink/55">Préparation des supports…</p>';
  await Promise.race([Promise.all(['700 40px Poppins', '600 40px Poppins', '500 40px Inter', '600 40px Inter'].map(f => document.fonts.load(f))), new Promise(r => setTimeout(r, 4000))]).catch(() => {});
  const a = await preparerDonnees({ supabase, communeId });
  const carte = 'bg-white border border-mango-100 rounded-xl p-4 shadow-sm';
  const b1 = 'bg-brand text-white rounded-lg px-3 py-2 text-sm font-semibold', b2 = 'border border-brand/20 text-ink bg-white rounded-lg px-3 py-2 text-sm font-semibold';
  const imprimes = ['affiche', 'affiche_eco', 'flyer'], images = ['post_1350', 'post_1080'];
  root.innerHTML = `<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,300px),1fr));gap:16px">
    ${imprimes.map(k => `<div class="${carte}" style="display:flex;flex-direction:column;gap:10px;min-width:0"><p class="text-sm font-bold text-ink">${FORMATS[k].nom}</p><div data-apercu="${k}" style="display:flex;gap:6px"></div><div style="display:flex;flex-wrap:wrap;gap:8px"><button type="button" data-imprimer="${k}" class="${b1}">Imprimer</button><button type="button" data-pdf="${k}" class="${b2}">Télécharger le PDF</button><button type="button" data-partager="${k}" class="${b2}">Partager</button></div><p data-st="${k}" class="text-xs text-ink/60" aria-live="polite" style="min-height:16px"></p></div>`).join('')}
    ${images.map(k => `<div class="${carte}" style="display:flex;flex-direction:column;gap:10px;min-width:0"><p class="text-sm font-bold text-ink">${FORMATS[k].nom}</p><div data-apercu="${k}"></div><div style="display:flex;flex-wrap:wrap;gap:8px"><button type="button" data-png="${k}" class="${b1}">Enregistrer l'image</button><button type="button" data-partager="${k}" class="${b2}">Partager</button></div><p data-st="${k}" class="text-xs text-ink/60" aria-live="polite" style="min-height:16px"></p></div>`).join('')}
    <div class="${carte}" style="display:flex;flex-direction:column;gap:10px;min-width:0"><p class="text-sm font-bold text-ink">Légende du post de lancement</p><textarea id="com-lg" aria-label="Légende" class="w-full border border-mango-100 rounded-lg px-2.5 py-2 text-sm bg-white" style="min-height:300px">${esc(legendePost(a, 'fb'))}</textarea><div style="display:flex;flex-wrap:wrap;gap:8px"><button type="button" data-lg="fb" class="${b1}">Copier pour Facebook</button><button type="button" data-lg="ig" class="${b2}">Copier pour Instagram</button></div><p data-st="lg" class="text-xs text-ink/60" aria-live="polite" style="min-height:16px"></p></div>
    <div class="${carte}" style="display:flex;flex-direction:column;gap:10px;min-width:0"><p class="text-sm font-bold text-ink">Mail aux habitants</p><p class="text-xs text-ink/55"><b>Objet :</b> Réservez vos livres et vos sorties depuis le canapé</p><iframe title="Aperçu du mail" id="com-mail" style="width:100%;height:300px;border:1px solid #F1DFC6;border-radius:8px;background:#fff"></iframe><div style="display:flex;flex-wrap:wrap;gap:8px"><button type="button" data-mail="copier" class="${b1}">Copier le mail</button><button type="button" data-mail="html" class="${b2}">Télécharger le HTML</button></div><p class="text-[11px] text-ink/45">Envoie-le depuis ton outil habituel et garde le lien de désinscription. BliGO n'envoie rien et ne reçoit pas ta liste.</p><p data-st="mail" class="text-xs text-ink/60" aria-live="polite" style="min-height:16px"></p></div>
    <div class="${carte}" style="display:flex;flex-direction:column;gap:10px;min-width:0"><p class="text-sm font-bold text-ink">Texte pour le bulletin municipal</p><textarea id="com-bull" aria-label="Texte du bulletin" class="w-full border border-mango-100 rounded-lg px-2.5 py-2 text-sm bg-white" style="min-height:300px">${esc(texteBulletin(a))}</textarea><div><button type="button" data-bull="1" class="${b1}">Copier le texte</button></div><p data-st="bull" class="text-xs text-ink/60" aria-live="polite" style="min-height:16px"></p></div>
  </div>`;
  document.getElementById('com-mail').srcdoc = mailHtml(a);
  const FICHIER = { affiche: 'affiche-bligo.pdf', affiche_eco: 'affiche-econome-bligo.pdf', flyer: 'flyer-bligo.pdf', post_1350: 'post-bligo-1080x1350.png', post_1080: 'post-bligo-1080x1080.png' };
  const apercus = [...imprimes, ...images];
  for (const k of apercus) {
    const zone = root.querySelector(`[data-apercu="${k}"]`), f = FORMATS[k];
    for (let p = 0; p < f.pages; p++) { const cv = await rendre(k, a, p); cv.style.cssText = `width:${f.pages > 1 ? '50%' : '100%'};height:auto;border-radius:6px;border:1px solid #F1DFC6;display:block;min-width:0`; zone.appendChild(cv); }
  }
  const st = k => root.querySelector(`[data-st="${k}"]`);
  const copier = async (t, k, ok) => { try { await navigator.clipboard.writeText(t); st(k).textContent = ok; } catch (e) { st(k).textContent = 'Copie impossible : sélectionne le texte à la main.'; } };
  root.onclick = async e => {
    const b = e.target.closest('button'); if (!b) return;
    const d = b.dataset;
    try {
      if (d.imprimer) {
        const f = FORMATS[d.imprimer], urls = [];
        st(d.imprimer).textContent = 'Préparation…';
        for (let p = 0; p < f.pages; p++) urls.push((await rendre(d.imprimer, a, p)).toDataURL('image/jpeg', .92));
        imprimerImages(urls, f.w / 72 * 25.4, f.h / 72 * 25.4);
        st(d.imprimer).textContent = '';
      }
      if (d.pdf) { st(d.pdf).textContent = 'Préparation du PDF…'; telecharger(await creerPdf(d.pdf, a), FICHIER[d.pdf]); st(d.pdf).textContent = 'PDF enregistré.'; }
      if (d.png) { telecharger(await versBlob(await rendre(d.png, a), 'image/png'), FICHIER[d.png]); st(d.png).textContent = 'Image enregistrée.'; }
      if (d.partager) {
        const k = d.partager, f = FORMATS[k];
        st(k).textContent = 'Préparation…';
        await partager(f.image ? await versBlob(await rendre(k, a), 'image/png') : await creerPdf(k, a), FICHIER[k], telecharger, st(k));
        if (st(k).textContent === 'Préparation…') st(k).textContent = '';
      }
      if (d.lg) {
        const courant = document.getElementById('com-lg').value;
        const t = d.lg === 'fb' ? courant : courant.replace(`👉 Téléchargez l'appli ici : ${LIEN}`, '👉 Le lien de téléchargement est dans notre bio !');
        await copier(t, 'lg', d.lg === 'fb' ? 'Légende Facebook copiée.' : 'Légende Instagram copiée. Pense à mettre le lien dans la bio ou en story.');
      }
      if (d.bull) await copier(document.getElementById('com-bull').value, 'bull', 'Texte copié.');
      if (d.mail === 'html') { telecharger(new Blob([mailHtml(a)], { type: 'text/html' }), 'mail-bligo.html'); st('mail').textContent = 'Fichier enregistré.'; }
      if (d.mail === 'copier') {
        const html = mailHtml(a);
        await navigator.clipboard.write([new ClipboardItem({ 'text/html': new Blob([html], { type: 'text/html' }), 'text/plain': new Blob([document.getElementById('com-mail').contentDocument.body.innerText], { type: 'text/plain' }) })]);
        st('mail').textContent = 'Mail copié : colle-le dans ton e-mail.';
      }
    } catch (err) { console.error(err); const k = d.imprimer || d.pdf || d.png || d.partager || (d.mail ? 'mail' : d.bull ? 'bull' : 'lg'); st(k).textContent = "Ça n'a pas marché, réessaie dans un instant."; }
  };
  return a;
}
