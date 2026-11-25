// Recherche tolérante aux fautes (25/11/2026, demande du Tampon) : l'usager
// tape « guy muse » et retrouve Guillaume Musso, « harry poter » retrouve
// Harry Potter, « monopoli » retrouve le jeu Monopoly.
// Trois niveaux de rapprochement, du plus sûr au plus large :
//   1. le mot commence par ce qui est tapé (« muss » → Musso) ;
//   2. ça se prononce pareil, en français (« guy » → Guillaume, « muse » → Musso) ;
//   3. une ou deux lettres de travers (« potetr » → Potter).
// Module pur (pas de DOM ni de Supabase) : testable avec Node.
(function (root) {
  const MOTS_VIDES = new Set(['le', 'la', 'les', 'l', 'de', 'du', 'des', 'd', 'un', 'une', 'et', 'a', 'au', 'aux', 'en', 'the', 'of']);

  function normaliser(s) {
    return (s || '').toString().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/œ/g, 'oe').replace(/æ/g, 'ae').replace(/[^a-z0-9]+/g, ' ').trim();
  }

  function mots(s) {
    return normaliser(s).split(' ').filter(Boolean);
  }

  // Clé phonétique simplifiée pour le français : deux mots qui se prononcent
  // à peu près pareil donnent la même clé (ou l'une commence par l'autre).
  function phonetique(m, finale = true) {
    let s = m;
    if (/^\d+$/.test(s)) return s;
    s = s.replace(/^mac(?=[^aeiou]|$)/, 'mc').replace(/y/g, 'i').replace(/ph/g, 'f').replace(/th/g, 't').replace(/w/g, 'v')
      .replace(/qu/g, 'k').replace(/q/g, 'k').replace(/ck/g, 'k')
      .replace(/gu(?=[ei])/g, 'g').replace(/c(?=[ei])/g, 's').replace(/c/g, 'k')
      .replace(/ge(?=[aou])/g, 'j').replace(/g(?=[ei])/g, 'j')
      .replace(/eau/g, 'o').replace(/au/g, 'o').replace(/ai|ei/g, 'e')
      .replace(/[ae]n(?=[^aeiou]|$)/g, 'an').replace(/[ae]m(?=[bp])/g, 'an')
      .replace(/z/g, 's').replace(/x/g, 's').replace(/h/g, '')
      .replace(/(.)\1+/g, '$1');
    if (!finale) return s;
    if (s.length > 3) s = s.replace(/e$/, '');
    if (s.length > 3) s = s.replace(/[stdp]$/, '');
    return s;
  }

  function levenshtein(a, b) {
    if (a === b) return 0;
    let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
    for (let i = 1; i <= a.length; i++) {
      const cur = [i];
      for (let j = 1; j <= b.length; j++) {
        cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      }
      prev = cur;
    }
    return prev[b.length];
  }

  const erreursPermises = n => (n <= 3 ? 0 : n <= 5 ? 1 : 2);

  // Squelette de consonnes (première lettre gardée) : les voyelles sont là où
  // l'on se trompe le plus (« fridda » pour « Freida », « mcfaden »).
  function squelette(m) {
    const p = phonetique(m, false);
    return p[0] + p.slice(1).replace(/[aeiou]/g, '');
  }

  // Proximité entre un mot tapé et un mot du catalogue, de 0 (rien à voir) à 1.
  // Le mot peut être en cours de frappe : on compare aussi au début du mot.
  function proximite(tape, mot) {
    if (!tape || !mot) return 0;
    if (mot === tape) return 1;
    if (mot.startsWith(tape)) return tape.length >= 2 ? 0.95 : 0.5;
    const pt = phonetique(tape), pm = phonetique(mot);
    if (pt.length >= 2 && pm.startsWith(pt)) return 0.85;
    let best = 0;
    const max = erreursPermises(tape.length);
    if (max) {
      const n = tape.length;
      const d = Math.min(levenshtein(tape, mot), levenshtein(tape, mot.slice(0, n)),
        levenshtein(tape, mot.slice(0, n + 1)), levenshtein(tape, mot.slice(0, Math.max(1, n - 1))));
      if (d <= max) best = 0.8 - 0.05 * d;
    }
    // Seulement si la première lettre est la bonne et qu'il y a au moins une
    // voyelle tapée : sinon « zzqx » finissait par ressembler à Shakespeare.
    if (tape.length >= 4 && /[aeiouy]/.test(tape) && tape[0] === mot[0]) {
      const st = squelette(tape), sm = squelette(mot);
      if (st.length >= 3 && sm.startsWith(st)) best = Math.max(best, 0.7);
    }
    return best;
  }

  // Index par document, recalculé seulement si le document change.
  const cache = new Map();
  function indexDe(b) {
    const cle = b.id + '|' + b.title + '|' + b.author;
    const c = cache.get(b.id);
    if (c && c.cle === cle) return c;
    const titre = mots(b.title), auteur = mots(b.author);
    const autres = mots([b.collection, b.format, b.platform, b.category].filter(Boolean).join(' '));
    const entree = { cle, titre, auteur, autres, texte: normaliser([b.title, b.author].join(' ')) };
    cache.set(b.id, entree);
    return entree;
  }

  function motsCherches(query) {
    const t = mots(query);
    const utiles = t.filter(m => !MOTS_VIDES.has(m));
    return utiles.length ? utiles : t;
  }

  function meilleur(tape, liste) {
    let best = 0;
    for (const m of liste) { const p = proximite(tape, m); if (p > best) best = p; if (best === 1) break; }
    return best;
  }

  // Score d'un document pour une recherche : chaque mot tapé doit retrouver un
  // mot du titre, de l'auteur (ou, moins bien noté, de la collection / du type).
  function score(b, query) {
    const tapes = motsCherches(query);
    if (!tapes.length) return 0;
    const ix = indexDe(b);
    let total = 0;
    for (const t of tapes) {
      const p = Math.max(meilleur(t, ix.titre), meilleur(t, ix.auteur), 0.9 * meilleur(t, ix.autres));
      if (p < 0.6) return 0;
      total += p;
    }
    let s = total / tapes.length;
    if (ix.texte.includes(normaliser(query))) s += 0.5;
    return s;
  }

  // Documents qui ressemblent à la recherche, du plus proche au moins proche.
  function chercher(books, query, seuil = 0.6) {
    return books.map(book => ({ book, score: score(book, query) }))
      .filter(r => r.score >= seuil)
      .sort((a, b) => b.score - a.score);
  }

  // Propositions sous la barre de recherche : auteurs puis documents.
  function suggestions(books, query, { auteurs: maxA = 3, documents: maxD = 5 } = {}) {
    const tapes = motsCherches(query);
    if (!tapes.length || normaliser(query).length < 2) return { auteurs: [], documents: [] };
    const parAuteur = new Map();
    for (const b of books) {
      if (!b.author) continue;
      const k = normaliser(b.author);
      if (!parAuteur.has(k)) parAuteur.set(k, { nom: b.author, n: 0, mots: mots(b.author) });
      parAuteur.get(k).n++;
    }
    const auteurs = [];
    for (const a of parAuteur.values()) {
      let total = 0, ok = true;
      for (const t of tapes) { const p = meilleur(t, a.mots); if (p < 0.6) { ok = false; break; } total += p; }
      if (ok) auteurs.push({ nom: a.nom, n: a.n, score: total / tapes.length });
    }
    auteurs.sort((x, y) => y.score - x.score || y.n - x.n);
    const gardes = auteurs.slice(0, maxA);
    // Pas deux fois la même info (retour de Mégane, 25/11/2026) : si l'auteur
    // est proposé, ses livres ne sont pas répétés en dessous, sauf ceux dont
    // le titre correspond aussi à la recherche. Toucher l'auteur les affiche.
    const deCesAuteurs = new Set(gardes.map(a => normaliser(a.nom)));
    const titreCorrespond = b => { const t = indexDe(b).titre; return tapes.every(m => meilleur(m, t) >= 0.6); };
    const documents = chercher(books, query)
      .filter(r => !deCesAuteurs.has(normaliser(r.book.author)) || titreCorrespond(r.book))
      .slice(0, maxD);
    return { auteurs: gardes, documents };
  }

  const api = { normaliser, phonetique, proximite, score, chercher, suggestions };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.BligoRecherche = api;
})(typeof window !== 'undefined' ? window : globalThis);
