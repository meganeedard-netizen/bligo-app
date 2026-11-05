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
export function texte(c, t, x, y, { size, weight = 700, color = INK, font = 'Poppins', largeur = W - 2 * x, interligne = 1.05, max = 99 }) {
  c.fillStyle = color; c.textBaseline = 'top';
  c.font = `${weight} ${size}px ${font}, Arial, sans-serif`;
  let ls = lignes(c, t, largeur);
  if (ls.length > max) { ls = ls.slice(0, max); ls[max - 1] = ls[max - 1].replace(/\s*\S*$/, '') + '…'; }
  ls.forEach((l, i) => c.fillText(l, x, y + i * size * interligne));
  return y + ls.length * size * interligne;
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
function couverture(c, livre, x, y, w, h, n = 0) {
  if (livre._img) return image(c, livre._img, x, y, w, h, w * .025);
  c.fillStyle = COULEURS[n % COULEURS.length]; arrondi(c, x, y, w, h, w * .025); c.fill();
  const s = Math.round(w * .11);
  const fin = texte(c, livre.title, x + w * .1, y + w * .12, { size: s, color: '#fff', largeur: w * .8, interligne: 1.15, max: 6 });
  texte(c, livre.author || '', x + w * .1, Math.max(fin + s, y + h - w * .2), { size: Math.round(s * .55), weight: 500, font: 'Inter', color: '#fff', largeur: w * .8, max: 2 });
}
function entete(c, a, couleur) {
  const m = 40 * 4 / 3;
  if (a.logo) {
    c.fillStyle = '#fff'; c.beginPath(); c.arc(m + 42, 46 + 42, 42, 0, Math.PI * 2); c.fill();
    const k = Math.min(68 / a.logo.width, 68 / a.logo.height), lw = a.logo.width * k, lh = a.logo.height * k;
    c.drawImage(a.logo, m + 42 - lw / 2, 88 - lh / 2, lw, lh);
  }
  const x = a.logo ? m + 100 : m;
  texte(c, 'Médiathèque Municipale', x, 50, { size: 26, weight: 600, color: couleur, largeur: W - x - m });
  const s = tailleQuiTient(c, deCommune(a.nom), 34, 20, W - x - m, 1);
  texte(c, deCommune(a.nom), x, 84, { size: s, color: couleur, largeur: W - x - m, max: 1 });
}
function pied(c, a, couleur, t) {
  const m = 40 * 4 / 3;
  texte(c, t, m, H - 92, { size: 34, weight: 600, color: couleur, largeur: W - 2 * m - 110 });
  c.fillStyle = '#fff'; arrondi(c, W - m - 90, H - 40 - 84, 90, 84, 16); c.fill();
  if (a.bligo) {
    const k = Math.min(78 / a.bligo.width, 72 / a.bligo.height), lw = a.bligo.width * k, lh = a.bligo.height * k;
    c.drawImage(a.bligo, W - m - 45 - lw / 2, H - 40 - 42 - lh / 2, lw, lh);
  }
}

const M = 40 * 4 / 3;
const DESSIN = {
  coeur(c, a, d) {
    c.fillStyle = INK; c.fillRect(0, 0, W, H);
    entete(c, a, '#fff');
    texte(c, 'Notre coup de cœur', M, 160, { size: 100, color: MANGUE, largeur: 700 });
    const h = 880, w = h / 1.5;
    couverture(c, d.livre, (W - w) / 2 + 10, 372, w, h);
    pied(c, a, '#fff', "");
    texte(c, 'À réserver', M, H - 136, { size: 34, weight: 600, color: '#fff', largeur: 190 });
    texte(c, "sur l'appli BliGO", M, H - 92, { size: 26, weight: 500, color: '#fff', font: 'Inter', largeur: 200, max: 2 });
  },
  nouveautes(c, a, d) {
    c.fillStyle = degrade(c, 0, 0, W, H); c.fillRect(0, 0, W, H);
    entete(c, a, INK);
    texte(c, 'Du nouveau en rayon.', M, 160, { size: 100, largeur: 700 });
    const w = 246, h = w * 1.5, g = 18;
    d.livres.slice(0, 4).forEach((l, i) => couverture(c, l, (W - 2 * w - g) / 2 + (i % 2) * (w + g), 410 + (i >> 1) * (h + g), w, h, i));
    pied(c, a, INK, "À réserver sur l'appli");
  },
  evenement(c, a, d) {
    const e = new Date(d.ev.event_date);
    c.fillStyle = CREME; c.fillRect(0, 0, W, H);
    entete(c, a, INK);
    c.fillStyle = degrade(c, M, 230, 340, 340); arrondi(c, M, 230, 340, 340, 34); c.fill();
    const jour = JOURS[e.getDay()];
    texte(c, jour[0].toUpperCase() + jour.slice(1), M + 34, 260, { size: 40, weight: 600, color: '#fff', largeur: 290 });
    texte(c, String(e.getDate()), M + 34, 316, { size: 130, color: '#fff', largeur: 290 });
    texte(c, MOIS[e.getMonth()], M + 34, 484, { size: 40, weight: 600, color: '#fff', largeur: 290 });
    const s = tailleQuiTient(c, d.ev.title, 118, 64, W - 2 * M, 3);
    const fin = texte(c, d.ev.title, M, 630, { size: s, largeur: W - 2 * M, max: 3 });
    const places = d.ev.max_seats ? ` ${d.ev.max_seats} places.` : '';
    texte(c, `${plage(d.ev)[0].toUpperCase()}${plage(d.ev).slice(1)}${d.ev.location ? ', ' + d.ev.location : ''}.${places}`, M, fin + 26, { size: 36, weight: 500, font: 'Inter', color: GRIS, largeur: W - 2 * M, interligne: 1.3, max: 3 });
    pied(c, a, INK, 'Inscrivez-vous sur BliGO');
  },
  mois(c, a, d) {
    c.fillStyle = CREME; c.fillRect(0, 0, W, H);
    entete(c, a, INK);
    texte(c, 'À venir près de chez vous', M, 168, { size: 88, largeur: 800 });
    d.evs.slice(0, 4).forEach((ev, i) => {
      const e = new Date(ev.event_date), y = 400 + i * 196;
      c.fillStyle = '#fff'; arrondi(c, M, y, W - 2 * M, 176, 28); c.fill();
      c.textAlign = 'center';
      texte(c, String(e.getDate()), M + 90, y + 28, { size: 66, color: ROSE, largeur: 160 });
      texte(c, MOIS_COURT[e.getMonth()], M + 90, y + 104, { size: 26, weight: 600, color: ROSE, largeur: 170 });
      c.textAlign = 'left';
      const fin = texte(c, ev.title, M + 190, y + 36, { size: 38, largeur: W - 2 * M - 220, interligne: 1.12, max: 2 });
      texte(c, heure(e), M + 190, fin + 6, { size: 28, weight: 500, font: 'Inter', color: GRIS, largeur: 500, max: 1 });
    });
    pied(c, a, INK, 'Inscrivez-vous sur BliGO');
  },
  vacances(c, a) {
    c.fillStyle = degrade(c, 0, 0, W, H); c.fillRect(0, 0, W, H);
    entete(c, a, INK);
    const fin = texte(c, 'Votre pile\nde lecture\npour les', M, 220, { size: 140, largeur: W - 2 * M });
    texte(c, 'vacances ?', M, fin, { size: 140, color: '#fff' });
    texte(c, 'Réservez-la depuis le canapé.', M, fin + 190, { size: 46, weight: 600, largeur: W - 2 * M });
    pied(c, a, INK, "Sur l'appli BliGO");
  },
  carte(c, a) {
    c.fillStyle = INK; c.fillRect(0, 0, W, H);
    entete(c, a, '#fff');
    texte(c, 'Votre carte, toujours sur vous.', M, 190, { size: 104, color: '#fff', largeur: W - 2 * M });
    const x = M, y = 590, w = W - 2 * M, h = 540;
    c.fillStyle = degrade(c, x, y, w, h); arrondi(c, x, y, w, h, 44); c.fill();
    c.save(); arrondi(c, x, y, w, h, 44); c.clip(); c.fillStyle = 'rgba(255,255,255,.14)'; c.beginPath(); c.arc(x + w - 70, y + 80, 150, 0, Math.PI * 2); c.fill(); c.restore();
    texte(c, 'Carte de médiathèque', x + 56, y + 56, { size: 34, weight: 600, color: '#fff', largeur: w - 112 });
    texte(c, 'Dans votre téléphone.', x + 56, y + 108, { size: 62, color: '#fff', largeur: w - 112 });
    c.fillStyle = '#fff'; arrondi(c, x + 56, y + 240, 240, 240, 26); c.fill();
    const n = 7, t = 180 / n; c.fillStyle = INK;
    [1,1,1,0,1,1,1, 1,0,1,0,1,0,1, 1,1,1,0,1,1,1, 0,0,0,1,0,1,0, 1,0,1,0,1,1,0, 0,1,0,1,0,1,1, 1,1,0,1,1,0,1].forEach((v, i) => { if (v) c.fillRect(x + 86 + (i % n) * t, y + 270 + Math.floor(i / n) * t, t - 3, t - 3); });
    texte(c, 'Présentez-la à la médiathèque pour emprunter vos livres.', x + 340, y + 280, { size: 40, weight: 600, color: '#fff', font: 'Inter', largeur: w - 396, interligne: 1.25 });
    pied(c, a, '#fff', "Sur l'appli BliGO");
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
    supabase.from('books').select('title, author, cover_url').eq('commune_id', communeId).not('cover_url', 'is', null).order('created_at', { ascending: false }).limit(4),
    supabase.from('events').select('title, event_date, location, max_seats, duration_minutes').eq('commune_id', communeId).gte('event_date', maintenant).order('event_date').limit(8),
  ]);

  const [logo, bligo] = await Promise.all([chargerImage(commune?.logo_url), chargerImage('img/bligo-logo.png')]);
  etat = { a: { nom: commune?.name || '', logo, bligo } };

  const livresNouv = (nouv && nouv.length) ? nouv : (recents || []);
  const posts = [];
  if (coeurs?.length) posts.push({ id: 'coeur', type: 'coeur', titre: 'Coup de cœur', quand: `${coeurs.length} coup${coeurs.length > 1 ? 's' : ''} de cœur dans ton catalogue`, livre: coeurs[0], options: coeurs.map(l => ({ label: l.title, val: l })) });
  if (livresNouv.length) posts.push({ id: 'nouveautes', type: 'nouveautes', titre: 'Nouveautés', quand: (nouv && nouv.length) ? 'Tes dernières nouveautés' : 'Tes derniers documents ajoutés', livres: livresNouv });
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
