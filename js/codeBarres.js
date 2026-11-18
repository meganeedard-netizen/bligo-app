// BliGO : dessin de codes-barres Code 128 en SVG (18/11/2026).
// Code 128 = lu par toutes les douchettes et par la caméra du logiciel.
// Jeu B pour le texte, bascule en jeu C (2 chiffres par motif, plus compact)
// pour la suite de chiffres finale : ABY00001234 tient sur une petite étiquette.

const MOTIFS = [
  '212222', '222122', '222221', '121223', '121322', '131222', '122213', '122312', '132212', '221213',
  '221312', '231212', '112232', '122132', '122231', '113222', '123122', '123221', '223211', '221132',
  '221231', '213212', '223112', '312131', '311222', '321122', '321221', '312212', '322112', '322211',
  '212123', '212321', '232121', '111323', '131123', '131321', '112313', '132113', '132311', '211313',
  '231113', '231311', '112133', '112331', '132131', '113123', '113321', '133121', '313121', '211331',
  '231131', '213113', '213311', '213131', '311123', '311321', '331121', '312113', '312311', '332111',
  '314111', '221411', '431111', '111224', '111422', '121124', '121421', '141122', '141221', '112214',
  '112412', '122114', '122411', '142112', '142211', '241211', '221114', '413111', '241112', '134111',
  '111242', '121142', '121241', '114212', '124112', '124211', '411212', '421112', '421211', '212141',
  '214121', '412121', '111143', '111341', '131141', '114113', '114311', '411113', '411311', '113141',
  '114131', '311141', '411131', '211412', '211214', '211232',
];
const STOP = '2331112';
const START_B = 104, START_C = 105, VERS_C = 99, VERS_B = 100;

// Valeurs des symboles (sans la clé de contrôle ni le stop).
function symboles(texte) {
  if (!/^[\x20-\x7E]+$/.test(texte)) throw new Error('Caractère non imprimable dans le code : ' + texte);
  const tousChiffres = /^\d+$/.test(texte);
  if (tousChiffres && texte.length % 2 === 0 && texte.length >= 2) {
    const v = [START_C];
    for (let i = 0; i < texte.length; i += 2) v.push(Number(texte.slice(i, i + 2)));
    return v;
  }
  // Partie texte en jeu B, puis la plus longue suite paire de chiffres finale en jeu C.
  const fin = (texte.match(/\d+$/) || [''])[0];
  let nC = fin.length >= 4 ? fin.length - (fin.length % 2) : 0;
  const partieB = texte.slice(0, texte.length - nC), partieC = texte.slice(texte.length - nC);
  const v = [START_B, ...[...partieB].map(c => c.charCodeAt(0) - 32)];
  if (nC) {
    v.push(VERS_C);
    for (let i = 0; i < partieC.length; i += 2) v.push(Number(partieC.slice(i, i + 2)));
  }
  return v;
}

// Largeurs de modules alternées barre/espace, de la barre de départ au stop.
export function modulesCode128(texte) {
  const v = symboles(String(texte));
  const cle = v.reduce((s, x, i) => s + x * (i === 0 ? 1 : i), 0) % 103;
  return [...v, cle].map(x => MOTIFS[x]).join('') + STOP;
}

// SVG en millimètres : largeur et hauteur données, marge blanche de 10 modules
// de chaque côté (indispensable pour la lecture).
export function svgCode128(texte, largeurMm, hauteurMm) {
  const largeurs = modulesCode128(texte).split('').map(Number);
  const total = largeurs.reduce((s, n) => s + n, 0) + 20;
  const m = largeurMm / total;
  let x = 10 * m, rects = '';
  largeurs.forEach((w, i) => {
    if (i % 2 === 0) rects += `<rect x="${x.toFixed(3)}" y="0" width="${(w * m).toFixed(3)}" height="${hauteurMm}"/>`;
    x += w * m;
  });
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${largeurMm}mm" height="${hauteurMm}mm" viewBox="0 0 ${largeurMm} ${hauteurMm}" shape-rendering="crispEdges" fill="#000">${rects}</svg>`;
}

// Nombre de modules (pour vérifier qu'un code tient sur l'étiquette).
export function largeurModules(texte) {
  return modulesCode128(texte).split('').reduce((s, n) => s + Number(n), 0) + 20;
}
