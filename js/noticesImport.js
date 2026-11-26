// Import de notices bibliographiques (18/11/2026, demande de Bastia).
// Les fournisseurs des médiathèques (Electre, Colaco, RDM Vidéo, libraires…)
// livrent les notices des documents achetés en UNIMARC ou en MARC 21 :
// fichier ISO 2709 (.mrc, .iso, .dat, .uni) ou MARCXML (.xml).
// Ce module est pur (pas de DOM ni de Supabase) : testable avec Node.

const RT = 0x1D, FT = 0x1E, SF = 0x1F;

// Caractères diacritiques « non espaçants » placés AVANT la lettre, dans les
// vieux jeux de caractères des notices : ISO 5426 (UNIMARC) et MARC-8 (MARC 21).
const ISO5426 = { 0xC1: '̀', 0xC2: '́', 0xC3: '̂', 0xC4: '̃', 0xC5: '̄', 0xC6: '̆', 0xC7: '̇', 0xC8: '̈', 0xC9: '̈', 0xCA: '̊', 0xCD: '̋', 0xCF: '̌', 0xD0: '̧', 0xD3: '̨' };
const ISO5426_SPACING = { 0xE1: 'Æ', 0xE2: 'Đ', 0xE8: 'Ł', 0xE9: 'Ø', 0xEA: 'Œ', 0xF1: 'æ', 0xF2: 'đ', 0xF8: 'ł', 0xF9: 'ø', 0xFA: 'œ', 0xFB: 'ß', 0xA9: '‘', 0xB9: '’', 0xAA: '“', 0xBA: '”', 0xAB: '«', 0xBB: '»', 0xA4: '$', 0xA3: '£', 0xA5: '¥' };
const MARC8 = { 0xE1: '̀', 0xE2: '́', 0xE3: '̂', 0xE4: '̃', 0xE5: '̄', 0xE6: '̆', 0xE7: '̇', 0xE8: '̈', 0xE9: '̌', 0xEA: '̊', 0xEE: '̋', 0xF0: '̧', 0xF1: '̨' };
const MARC8_SPACING = { 0xA5: 'Æ', 0xB5: 'æ', 0xA6: 'Œ', 0xB6: 'œ', 0xA2: 'Ø', 0xB2: 'ø', 0xA1: 'Ł', 0xB1: 'ł', 0xC7: 'ß', 0xA3: 'Đ', 0xB3: 'đ' };

function decodeLegacy(bytes, marc8) {
  const comb = marc8 ? MARC8 : ISO5426, spacing = marc8 ? MARC8_SPACING : ISO5426_SPACING;
  let out = '', pending = '';
  for (const b of bytes) {
    if (b === 0x88 || b === 0x89 || b === 0x98 || b === 0x9C) continue; // début/fin de non-classement
    if (comb[b]) { pending += comb[b]; continue; }
    const ch = b < 0x80 ? String.fromCharCode(b) : (spacing[b] || String.fromCharCode(b));
    out += ch + pending; pending = '';
  }
  return out.normalize('NFC');
}

function makeDecoder(sampleBytes, marc8) {
  try {
    const utf = new TextDecoder('utf-8', { fatal: true });
    utf.decode(sampleBytes);
    return b => utf.decode(b);
  } catch {
    return b => decodeLegacy(b, marc8);
  }
}

const clean = s => String(s ?? '').replace(/[\u0088\u0089\u0098\u009C]/g, '').replace(/\s+/g, ' ').trim();

// ISO 2709 : longueurs et adresses en OCTETS (indispensable en UTF-8).
function parseIso2709(bytes) {
  const records = [];
  let start = 0;
  while (start < bytes.length) {
    while (start < bytes.length && (bytes[start] === 0x0A || bytes[start] === 0x0D || bytes[start] === 0x20)) start++;
    if (start + 24 > bytes.length) break;
    const ascii = (a, b) => String.fromCharCode(...bytes.subarray(a, b));
    const leader = ascii(start, start + 24);
    let length = parseInt(leader.slice(0, 5), 10);
    let end = start + length;
    // Longueur fausse (fichier retouché) : on se fie au séparateur de notice.
    if (!length || end > bytes.length || bytes[end - 1] !== RT) {
      end = bytes.indexOf(RT, start) + 1;
      if (end <= 0) end = bytes.length;
    }
    const rec = bytes.subarray(start, end);
    start = end;
    const base = parseInt(leader.slice(12, 17), 10);
    if (!base || base > rec.length) continue;
    const dirEnd = rec.indexOf(FT);
    const dir = String.fromCharCode(...rec.subarray(24, dirEnd > 0 ? dirEnd : base - 1));
    const dirTags = new Set(dir.match(/.{12}/g)?.map(e => e.slice(0, 3)) || []);
    const decode = makeDecoder(rec.subarray(base), dirTags.has('245') && !dirTags.has('200'));
    const fields = [];
    for (let i = 0; i + 12 <= dir.length; i += 12) {
      const tag = dir.slice(i, i + 3);
      const len = parseInt(dir.slice(i + 3, i + 7), 10);
      const pos = parseInt(dir.slice(i + 7, i + 12), 10);
      let raw = rec.subarray(base + pos, base + pos + len);
      if (raw[raw.length - 1] === FT) raw = raw.subarray(0, raw.length - 1);
      if (tag < '010') { fields.push({ tag, data: clean(decode(raw)) }); continue; }
      const ind1 = String.fromCharCode(raw[0] ?? 32), ind2 = String.fromCharCode(raw[1] ?? 32);
      const subs = [];
      let cur = null;
      for (let j = 2; j <= raw.length; j++) {
        if (j === raw.length || raw[j] === SF) {
          if (cur !== null) {
            const chunk = raw.subarray(cur, j);
            if (chunk.length) subs.push([String.fromCharCode(chunk[0]), clean(decode(chunk.subarray(1)))]);
          }
          cur = j + 1;
        }
      }
      fields.push({ tag, ind1, ind2, subs });
    }
    records.push({ leader, fields });
  }
  return records;
}

const xmlText = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'")
  .replace(/&#x([0-9a-f]+);/gi, (m, h) => String.fromCodePoint(parseInt(h, 16)))
  .replace(/&#(\d+);/g, (m, d) => String.fromCodePoint(+d)).replace(/&amp;/g, '&');

function parseMarcXml(text) {
  const records = [];
  const recRe = /<(?:\w+:)?record\b[^>]*>([\s\S]*?)<\/(?:\w+:)?record>/g;
  let m;
  while ((m = recRe.exec(text))) {
    const body = m[1];
    const leader = (body.match(/<(?:\w+:)?leader>([\s\S]*?)<\/(?:\w+:)?leader>/) || [])[1] || ''.padEnd(24);
    const fields = [];
    const fRe = /<(?:\w+:)?(controlfield|datafield)\b([^>]*)>([\s\S]*?)<\/(?:\w+:)?\1>/g;
    let f;
    while ((f = fRe.exec(body))) {
      const attr = n => (f[2].match(new RegExp(`${n}="([^"]*)"`)) || [])[1] || ' ';
      const tag = attr('tag');
      if (f[1] === 'controlfield') { fields.push({ tag, data: clean(xmlText(f[3])) }); continue; }
      const subs = [];
      const sRe = /<(?:\w+:)?subfield\b[^>]*code="([^"]*)"[^>]*>([\s\S]*?)<\/(?:\w+:)?subfield>/g;
      let s;
      while ((s = sRe.exec(f[3]))) subs.push([s[1], clean(xmlText(s[2]))]);
      fields.push({ tag, ind1: attr('ind1'), ind2: attr('ind2'), subs });
    }
    records.push({ leader: xmlText(leader).padEnd(24), fields });
  }
  return records;
}

// MARC 21 (notices américaines, certaines notices de DVD) : convertie vers
// les zones UNIMARC équivalentes pour n'avoir qu'une seule lecture ensuite.
function marc21ToUnimarc(rec) {
  const out = [];
  const sub = (f, c) => f.subs.filter(([k]) => k === c).map(([, v]) => v);
  const push = (tag, subs, ind1 = ' ', ind2 = ' ') => { const s = subs.filter(([, v]) => v); if (s.length) out.push({ tag, ind1, ind2, subs: s }); };
  const type = rec.leader[6];
  const docType = type === 'g' ? 'Images animées' : (type === 'j' || type === 'i') ? 'Enregistrement sonore' : (type === 'c' || type === 'd') ? 'Musique imprimée' : 'Texte imprimé';
  rec.fields.forEach(f => {
    if (!f.subs) return;
    const a = c => sub(f, c)[0] || null;
    switch (f.tag) {
      case '020': push('010', [['a', (a('a') || '').split(' ')[0]], ['d', a('c')]]); break;
      case '024': push('073', [['a', a('a')]]); break;
      case '041': sub(f, 'a').forEach(l => push('101', [['a', l]])); break;
      case '082': push('676', [['a', (a('a') || '').replace(/\//g, '')]]); break;
      case '100': case '110': { const [last, first] = (a('a') || '').replace(/[,.]$/, '').split(/,\s*/); push('700', [['a', last], ['b', first]]); break; }
      case '700': case '710': { const [last, first] = (a('a') || '').replace(/[,.]$/, '').split(/,\s*/); push('702', [['a', last], ['b', first], ['4', /trans/i.test(a('e') || '') ? '730' : /ill/i.test(a('e') || '') ? '440' : '']]); break; }
      case '245': push('200', [['a', [a('a'), a('n'), a('p')].filter(Boolean).join('. ').replace(/\s*[/:;]$/, '')], ['b', docType], ['e', (a('b') || '').replace(/\s*[/:;]$/, '')], ['f', (a('c') || '').replace(/\.$/, '')]], '1'); break;
      case '250': push('205', [['a', a('a')]]); break;
      case '260': case '264': if (f.tag === '260' || f.ind2 === '1') push('210', [['a', a('a')], ['c', (a('b') || '').replace(/[,:;]$/, '')], ['d', (a('c') || '').replace(/\.$/, '')]]); break;
      case '300': push('215', [['a', (a('a') || '').replace(/\s*[:;]$/, '')], ['c', (a('b') || '').replace(/\s*;$/, '')], ['d', a('c')]]); break;
      case '490': case '830': push('225', [['a', (a('a') || '').replace(/\s*;$/, '')], ['v', a('v')]], '2'); break;
      case '505': (a('a') || '').split(/\s*--\s*/).forEach(t => push('327', [['a', t.replace(/[.\s]+$/, '')]], '1')); break;
      case '520': push('330', [['a', a('a')]]); break;
      case '521': push('333', [['a', a('a')]]); break;
      case '650': case '651': push(f.tag === '651' ? '607' : '606', [['a', a('a')], ['x', a('x')], ['y', a('z')], ['z', a('y')]]); break;
      case '655': push('608', [['a', a('a')]]); break;
      case '852': push('995', [['k', [a('h'), a('i')].filter(Boolean).join(' ')], ['f', a('p')]]); break;
      default: break;
    }
  });
  if (!out.some(f => f.tag === '200')) push('200', [['b', docType]], '1');
  return { leader: rec.leader, fields: out, from: 'marc21' };
}

function isMarc21(rec) {
  const tags = new Set(rec.fields.map(f => f.tag));
  return tags.has('245') && !tags.has('200');
}

export function lireFichierNotices(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  const head = new TextDecoder('utf-8').decode(bytes.subarray(0, 400)).replace(/^﻿/, '').trimStart();
  const records = head.startsWith('<') ? parseMarcXml(new TextDecoder('utf-8').decode(bytes)) : parseIso2709(bytes);
  return records.map(r => isMarc21(r) ? marc21ToUnimarc(r) : r);
}

// Même lecture que la notice BnF du catalogage (bnfSruQuery dans admin.html).
export function noticeVersFiche(rec) {
  const all = tag => rec.fields.filter(f => f.tag === tag && f.subs);
  const one = tag => all(tag)[0] || null;
  const get = (f, c) => f?.subs.find(([k]) => k === c)?.[1] || null;
  const getAll = (f, codes) => f ? f.subs.filter(([k]) => codes.includes(k)).map(([, v]) => v).filter(Boolean) : [];

  const f010 = one('010'), f200 = one('200'), f210 = one('210'), f215 = one('215'), f225 = one('225');
  const f214s = all('214');
  const f214main = f214s.find(f => f.ind2 !== '3') || null;
  const f214printer = f214s.find(f => f.ind2 === '3') || null;
  const f073 = one('073');

  // Colaco et d'autres fournisseurs rejettent l'article en fin de titre :
  // « Bataille d'Oslo (La) - Chapitre 3 » devient « La Bataille d'Oslo - Chapitre 3 ».
  let title = (get(f200, 'a') || '').replace(/^(.+?)\s*\((Le|La|Les|L'|L’|Un|Une|Des|The|A|An)\)(.*)$/,
    (m, t, art, rest) => (/'|’$/.test(art) ? art + t : art + ' ' + t) + rest) || null;
  if (!title) return null;
  const partNum = get(f200, 'h'), partName = get(f200, 'i');
  // Séries (26/11/2026) : 461 $t/$v, sinon 200 $a + numéro de tome en 200 $h.
  const f461 = one('461');
  const series_name = (get(f461, 't') || (partNum && /\d/.test(partNum) ? title : null) || '').trim() || null;
  const seriesNumRaw = String(get(f461, 'v') || partNum || '').match(/(\d+(?:[.,]\d+)?)/);
  const series_number = series_name && seriesNumRaw ? Number(seriesNumRaw[1].replace(',', '.')) : null;
  const contents = [...all('327').flatMap(f => getAll(f, ['a'])), ...all('464').map(f => get(f, 't'))]
    .map(t => (t || '').replace(/\s*[;.]\s*$/, '').trim()).filter(Boolean).join('\n') || null;
  if (partNum || partName) title = [title, [partNum, partName].filter(Boolean).join('. ')].join('. ');

  const author700 = one('700') || one('710') || one('701');
  const last = get(author700, 'a'), first = get(author700, 'b');
  const responsibility = (get(f200, 'f') || '').split(/,\s*/).filter(p => p && !/^\p{Ll}/u.test(p)).join(', ') || null;
  const secondary = [...getAll(f200, ['g']), ...all('702').map(f => [get(f, 'b'), get(f, 'a')].filter(Boolean).join(' ') + (get(f, '4') === '730' ? ' (trad.)' : get(f, '4') === '440' ? ' (ill.)' : ''))];
  const translator = secondary.find(t => /trad/i.test(t))?.replace(/^.*?trad[^\s]*\s*(de l'[^\s]+ par|par|de)?\s*/i, '').replace(/\s*\(trad\.\)$/, '') || null;
  const illustrator = secondary.find(t => /(ill|photo|dessin)/i.test(t))?.replace(/\s*\(ill\.\)$/, '') || null;

  const rawDate = get(f210, 'd') || get(f214main, 'd') || '';
  const pagesRaw = get(f215, 'a') || '';
  const bindingRaw = get(f010, 'b') || '';
  const f345 = one('345');
  const priceRaw = get(f010, 'd') || get(f345, 'd') || '';
  const priceMatch = priceRaw.match(/(\d+(?:[.,]\d{1,2})?)\s*(EUR|€)/i);
  const ages = all('333').map(f => (get(f, 'a') || '').match(/(\d{1,2})\s*ans/i)?.[1]).filter(Boolean).map(Number);
  const genreTerms = [...all('606'), ...all('608'), ...all('610'), ...all('615')].map(f => get(f, 'a')).filter(Boolean).join(' ');
  const subjects = [...all('606'), ...all('607')].map(f => getAll(f, ['a', 'x', 'y', 'z']).join(' -- ')).filter(Boolean).join(' ; ') || null;

  // Exemplaires livrés équipés (zone 995) : code-barres $f, cote $k.
  const copies = all('995').map(f => ({ barcode: get(f, 'f'), cote: get(f, 'k') }));

  // DVD/CD : pas d'ISBN, l'EAN est en 073 ou, chez Colaco, en 345 $b.
  const isbn = (get(f010, 'a') || '').replace(/[^\dX]/gi, '') || (get(f073, 'a') || '').replace(/\D/g, '')
    || ((get(f345, 'b') || '').replace(/\D/g, '').match(/^\d{8,14}$/)?.[0]) || null;
  // Type de document : 200 $b, sinon la position 6 du label (g = vidéo, i/j = son, c/d = partition).
  const t6 = (rec.leader || '')[6];
  const docType = get(f200, 'b') || (t6 === 'g' ? 'Images animées' : (t6 === 'i' || t6 === 'j') ? 'Enregistrement sonore' : (t6 === 'c' || t6 === 'd') ? 'Musique imprimée' : null);

  return {
    docType,
    extent: pagesRaw || null,
    title,
    author: last ? [first, last].filter(Boolean).join(' ') : responsibility,
    authorLastName: last,
    isbn,
    publisher: (get(f210, 'c') || get(f214main, 'c') || '').replace(/^\[|\]$/g, '').trim() || null,
    published_date: rawDate.match(/\d{4}/)?.[0] || rawDate || null,
    legal_deposit: rawDate || null,
    printer: get(f210, 'g') || get(f214printer, 'a') || null,
    page_count: Number(pagesRaw.match(/(\d+)\s*p/)?.[1]) || null,
    language: get(one('101'), 'a'),
    summary: get(one('330'), 'a'),
    dewey: get(one('676'), 'a'),
    binding: /rel/i.test(bindingRaw) ? 'Relié' : /cart/i.test(bindingRaw) ? 'Cartonné' : /br/i.test(bindingRaw) ? 'Broché' : (bindingRaw || null),
    collection: f225 ? [get(f225, 'a'), get(f225, 'v')].filter(Boolean).join(', ') || null : null,
    series_name,
    series_number,
    contents,
    dimensions: get(f215, 'd'),
    illustrations: get(f215, 'c'),
    subjects,
    price_cents: priceMatch ? Math.round(parseFloat(priceMatch[1].replace(',', '.')) * 100) : null,
    age_range: ages.length ? `Dès ${Math.min(...ages)} ans` : null,
    translator,
    illustrator,
    rawCategoryText: [genreTerms, subjects].filter(Boolean).join(' ') || null,
    copies,
  };
}
