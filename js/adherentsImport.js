// Lecture du fichier CSV des adhérents (05/11/2026). Pur : testable sans navigateur.
// Accepte séparateur ; , ou tabulation, et les intitulés de colonnes les plus courants.
const sansAccent = s => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
const COLONNES = {
  numero_carte: ['numero de carte', 'n de carte', 'numero carte', 'carte', 'numero adherent', 'numero d adherent', 'n adherent', 'numero abonne', 'n abonne', 'code barre', 'code-barres', 'code barres', 'numero', 'id'],
  nom_complet: ['nom complet', 'nom et prenom', 'nom prenom', 'prenom nom', 'adherent'],
  nom: ['nom', 'nom de famille'],
  prenom: ['prenom'],
  email: ['email', 'e-mail', 'mail', 'courriel', 'adresse mail', 'adresse e-mail', 'adresse email'],
  date_naissance: ['date de naissance', 'naissance', 'date naissance', 'ne le', 'nee le'],
  categorie: ['categorie', 'categorie tarifaire', 'tarif', 'type'],
  adhesion_jusqu_au: ['fin d adhesion', 'fin adhesion', 'date de fin', 'expiration', 'validite', 'adhesion jusqu au', 'date d expiration', 'fin de validite'],
};
function lireCsv(texte) {
  const t = String(texte).replace(/^﻿/, '');
  const premiere = t.split(/\r?\n/, 1)[0] || '';
  const sep = [';', '\t', ','].map(s => [s, premiere.split(s).length]).sort((a, b) => b[1] - a[1])[0][0];
  const lignes = []; let l = [], c = '', q = false;
  for (let i = 0; i < t.length; i++) {
    const x = t[i];
    if (q) { if (x === '"') { if (t[i + 1] === '"') { c += '"'; i++; } else q = false; } else c += x; }
    else if (x === '"') q = true;
    else if (x === sep) { l.push(c); c = ''; }
    else if (x === '\n' || x === '\r') { if (x === '\r' && t[i + 1] === '\n') i++; l.push(c); c = ''; lignes.push(l); l = []; }
    else c += x;
  }
  if (c !== '' || l.length) { l.push(c); lignes.push(l); }
  lignes.forEach((r, i) => { r.n = i + 1; });
  return lignes.filter(r => r.some(v => v.trim() !== ''));
}
// JJ/MM/AAAA, JJ-MM-AAAA, JJ.MM.AAAA ou AAAA-MM-JJ
export function lireDate(v) {
  const s = String(v ?? '').trim();
  let m = s.match(/^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})/), y, mo, d;
  if (m) { d = +m[1]; mo = +m[2]; y = +m[3]; }
  else { m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/); if (!m) return null; y = +m[1]; mo = +m[2]; d = +m[3]; }
  const o = new Date(Date.UTC(y, mo - 1, d));
  if (o.getUTCMonth() !== mo - 1 || o.getUTCDate() !== d) return null;
  return `${y}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}
function categorie(v) {
  const s = sansAccent(v);
  if (!s) return '';
  if (/famil/.test(s)) return 'famille';
  if (/grat|sans emploi|exon/.test(s)) return 'gratuit';
  if (/min|enfant|jeune|ado/.test(s)) return 'mineur';
  if (/maj|adulte/.test(s)) return 'majeur';
  return '';
}
// Renvoie { lignes, erreurs, colonnes } ; une ligne sans nom est écartée et signalée.
export function analyserCsv(texte) {
  const brut = lireCsv(texte);
  if (brut.length < 2) return { lignes: [], erreurs: ['Le fichier ne contient aucune ligne d\'adhérent.'], colonnes: {} };
  const tete = brut[0].map(h => sansAccent(h).replace(/[°'’_]/g, ' ').replace(/\s+/g, ' ').trim());
  const col = {};
  for (const [cle, noms] of Object.entries(COLONNES)) {
    let i = tete.findIndex(h => noms.includes(h));
    if (i >= 0) col[cle] = i;
  }
  if (col.nom_complet === undefined && col.nom === undefined) return { lignes: [], erreurs: ['Colonne du nom introuvable : le fichier doit contenir une colonne « Nom ».'], colonnes: col };
  const lignes = [], erreurs = [];
  const val = (r, k) => col[k] === undefined ? '' : String(r[col[k]] ?? '').trim();
  brut.slice(1).forEach(r => {
    const nom = val(r, 'nom_complet') || [val(r, 'prenom'), val(r, 'nom')].filter(Boolean).join(' ');
    if (!nom) { erreurs.push(`Ligne ${r.n} : nom manquant, ligne écartée.`); return; }
    const email = val(r, 'email').toLowerCase();
    const brutN = val(r, 'date_naissance'), brutF = val(r, 'adhesion_jusqu_au');
    const naissance = brutN ? lireDate(brutN) : '';
    const fin = brutF ? lireDate(brutF) : '';
    if (brutN && !naissance) erreurs.push(`Ligne ${r.n} : date de naissance illisible (${brutN}), gardée sans date.`);
    if (brutF && !fin) erreurs.push(`Ligne ${r.n} : date de fin d'adhésion illisible (${brutF}), gardée sans date.`);
    lignes.push({ numero_carte: val(r, 'numero_carte'), nom_complet: nom, email: /@/.test(email) ? email : '', date_naissance: naissance || '', tariff_category: categorie(val(r, 'categorie')), adhesion_jusqu_au: fin || '' });
  });
  return { lignes, erreurs, colonnes: col };
}
