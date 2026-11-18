// BliGO : bilan annuel de l'agenda culturel (18/11/2026, demande des Abymes).
// Données : RPC agenda_bilan (sql/add_bilan_agenda.sql). Totaux seulement,
// jamais de noms. Impression PDF via window.print (zone #print-bilan-area).

const MOIS = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const GRIS = '#c8c7c0';
// Ordre catégoriel fixe (palette validée daltonisme), jamais recyclé.
const SERIES = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#6250d6', '#e34948'];

const GENRES = [
  ['femme', 'Femmes', SERIES[0]],
  ['homme', 'Hommes', SERIES[1]],
  ['transgenre', 'Transgenres', SERIES[2]],
  ['non_precise', 'Ne souhaite pas préciser', SERIES[3]],
  ['non_renseigne', 'Non renseigné', GRIS],
];
const AGES = [
  ['enfant', 'Enfants', SERIES[0]],
  ['adulte', 'Adultes', SERIES[1]],
  ['senior', 'Seniors', SERIES[2]],
  ['non_renseigne', 'Non renseigné', GRIS],
];

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const nf = n => Number(n || 0).toLocaleString('fr-FR');
const pct = (a, b) => (b > 0 ? Math.round((a / b) * 100) : 0);

let dernierBilan = null;

function carte(titre, contenu, extra = '') {
  return `<div class="bilan-carte min-w-0 bg-white border border-[#E5E7EB] rounded-xl p-4 ${extra}">
    <p class="text-[11px] font-bold uppercase tracking-wide text-ink/50 mb-3">${titre}</p>${contenu}</div>`;
}

function tuile(valeur, libelle, sous = '') {
  return `<div class="bilan-tuile min-w-0 bg-white border border-[#E5E7EB] rounded-xl p-3">
    <p class="text-2xl font-bold text-ink leading-none">${valeur}</p>
    <p class="text-[11px] font-semibold text-ink/60 mt-1.5">${libelle}</p>
    ${sous ? `<p class="text-[10.5px] text-ink/45 mt-0.5">${sous}</p>` : ''}</div>`;
}

function evolution(actuel, precedent) {
  if (!precedent) return '';
  const d = Math.round(((actuel - precedent) / precedent) * 100);
  if (d === 0) return 'Stable par rapport à l\'an dernier';
  return `${d > 0 ? '▲ +' : '▼ '}${d} % par rapport à l'an dernier (${nf(precedent)})`;
}

// Anneau : segments séparés par un fin espace, libellé + valeur + % en légende.
function anneau(valeurs, defs) {
  const lignes = defs.map(([k, lib, coul]) => ({ k, lib, coul, n: Number(valeurs[k] || 0) })).filter(l => l.n > 0);
  const total = lignes.reduce((s, l) => s + l.n, 0);
  if (!total) return `<p class="text-xs text-ink/45">Pas encore de public identifié pour cette année.</p>`;
  const R = 42, C = 2 * Math.PI * R, ecart = lignes.length > 1 ? 1.2 : 0;
  let pos = 0;
  const arcs = lignes.map(l => {
    const long = (l.n / total) * C;
    const a = `<circle r="${R}" cx="60" cy="60" fill="none" stroke="${l.coul}" stroke-width="16"
      stroke-dasharray="${Math.max(long - ecart, 0.5)} ${C}" stroke-dashoffset="${-pos}" transform="rotate(-90 60 60)">
      <title>${esc(l.lib)} : ${nf(l.n)} (${pct(l.n, total)} %)</title></circle>`;
    pos += long;
    return a;
  }).join('');
  const legende = lignes.map(l => `<li class="flex items-center gap-2 text-xs text-ink/70">
      <span class="w-2.5 h-2.5 rounded-sm shrink-0" style="background:${l.coul}"></span>
      <span class="flex-1">${esc(l.lib)}</span><span class="font-semibold text-ink">${l.n && pct(l.n, total) === 0 ? '< 1' : pct(l.n, total)} %</span>
      <span class="text-ink/45 w-8 text-right">${nf(l.n)}</span></li>`).join('');
  return `<div class="flex items-center gap-4 flex-wrap">
    <svg viewBox="0 0 120 120" width="130" height="130" role="img" aria-label="Répartition">${arcs}
      <text x="60" y="58" text-anchor="middle" font-size="18" font-weight="700" fill="#1f2937">${nf(total)}</text>
      <text x="60" y="74" text-anchor="middle" font-size="9" fill="#6b7280">personnes</text></svg>
    <ul class="flex-1 min-w-[170px] flex flex-col gap-1.5">${legende}</ul></div>`;
}

// Barres horizontales (une seule série, une seule couleur).
function barres(lignes, { valeur, libelle, detail }) {
  const max = Math.max(1, ...lignes.map(valeur));
  return `<div class="flex flex-col gap-2">${lignes.map(l => `
    <div title="${esc(libelle(l))} : ${esc(detail(l))}">
      <div class="flex justify-between text-xs mb-0.5"><span class="text-ink/75">${esc(libelle(l))}</span><span class="text-ink/55">${esc(detail(l))}</span></div>
      <div class="h-2 bg-[#F1F1EE] rounded-full"><div class="h-2 rounded-full" style="width:${Math.max(2, (valeur(l) / max) * 100)}%;background:${SERIES[0]}"></div></div>
    </div>`).join('')}</div>`;
}

function colonnesMois(parMois) {
  const parM = Object.fromEntries(parMois.map(m => [m.mois, m]));
  const max = Math.max(1, ...parMois.map(m => m.public));
  return `<div class="flex items-end gap-1 h-32">${MOIS.map((lib, i) => {
    const m = parM[i + 1] || { n: 0, public: 0 };
    const h = m.public ? Math.max(3, (m.public / max) * 100) : 0;
    return `<div class="flex-1 flex flex-col items-center justify-end h-full" title="${lib} : ${nf(m.n)} événement(s), ${nf(m.public)} personnes">
      <span class="text-[9.5px] text-ink/55 mb-0.5">${m.public ? nf(m.public) : ''}</span>
      <div class="w-full max-w-[22px] rounded-t" style="height:${h}%;background:${SERIES[0]}"></div>
      <span class="text-[9.5px] text-ink/45 mt-1 border-t border-[#E5E7EB] w-full text-center pt-0.5">${lib}</span></div>`;
  }).join('')}</div>`;
}

function aRetenir(b) {
  const t = b.totaux, points = [];
  const passes = b.evenements.filter(e => e.passe);
  const avecJauge = passes.filter(e => e.places > 0);
  if (avecJauge.length) {
    const tri = [...avecJauge].sort((x, y) => y.inscrits / y.places - x.inscrits / x.places);
    const top = tri[0];
    points.push(`Le plus rempli : « ${esc(top.titre)} » (${pct(top.inscrits, top.places)} % de la jauge).`);
    const bas = tri[tri.length - 1];
    if (tri.length > 1 && pct(bas.inscrits, bas.places) < 30)
      points.push(`Le moins rempli : « ${esc(bas.titre)} » (${pct(bas.inscrits, bas.places)} % de la jauge).`);
  }
  if (b.par_type.length && t.evenements >= 3) {
    const p = b.par_type[0], part = pct(p.n, t.evenements);
    points.push(part >= 40
      ? `Peu de diversité : ${part} % des événements sont des « ${esc(p.type)} ».`
      : `${b.par_type.length} types d'événements différents, le plus fréquent (« ${esc(p.type)} ») en représente ${part} %.`);
    const fort = [...b.par_type].filter(x => x.n > 0).sort((x, y) => y.public / y.n - x.public / x.n)[0];
    if (fort && fort.public) points.push(`Le type qui attire le plus, en moyenne : « ${esc(fort.type)} » (${nf(Math.round(fort.public / fort.n))} personnes par séance).`);
  }
  if (b.repetes.length) points.push(`${b.repetes.length} événement(s) programmé(s) plusieurs fois dans l'année (voir plus bas).`);
  const g = b.genre || {}, nr = Number(g.non_renseigne || 0), tot = Object.values(g).reduce((s, n) => s + Number(n), 0);
  if (tot && nr / tot > 0.3) points.push(`Le genre n'est pas renseigné pour ${pct(nr, tot)} % du public : complète-le sur les fiches usagers pour un bilan plus juste.`);
  if (!points.length) return '';
  return carte('À retenir', `<ul class="flex flex-col gap-1.5">${points.map(p => `<li class="text-sm text-ink/80">• ${p}</li>`).join('')}</ul>`, 'md:col-span-2');
}

function tableauEvenements(evs) {
  if (!evs.length) return '';
  const lignes = evs.map(e => {
    const d = new Date(e.date);
    const jauge = e.places > 0 ? `${pct(e.inscrits, e.places)} %` : '';
    return `<tr class="border-t border-[#F1F1EE]">
      <td class="py-1.5 pr-2 whitespace-nowrap text-ink/55">${d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' })}</td>
      <td class="py-1.5 pr-2 text-ink">${esc(e.titre)}${e.audience === 'enfants' ? ' <span class="text-[10px] text-ink/45">(jeunesse)</span>' : ''}${e.passe ? '' : ' <span class="text-[10px] text-ink/45">(à venir)</span>'}</td>
      <td class="py-1.5 pr-2 text-ink/60">${esc(e.type)}</td>
      <td class="py-1.5 pr-2 text-right">${e.places > 0 ? nf(e.places) : ''}</td>
      <td class="py-1.5 pr-2 text-right">${nf(e.inscrits)}</td>
      <td class="py-1.5 pr-2 text-right">${e.presents ? nf(e.presents) : ''}</td>
      <td class="py-1.5 pr-2 text-right font-semibold">${nf(e.public)}</td>
      <td class="py-1.5 text-right">${jauge}</td></tr>`;
  }).join('');
  return carte('Détail par événement', `<div class="overflow-x-auto"><table class="w-full text-xs">
    <thead><tr class="text-[10.5px] uppercase tracking-wide text-ink/45 text-left">
      <th class="pb-1.5 pr-2 font-semibold">Date</th><th class="pb-1.5 pr-2 font-semibold">Événement</th><th class="pb-1.5 pr-2 font-semibold">Type</th>
      <th class="pb-1.5 pr-2 font-semibold text-right">Places</th><th class="pb-1.5 pr-2 font-semibold text-right">Inscrits</th>
      <th class="pb-1.5 pr-2 font-semibold text-right">Présents</th><th class="pb-1.5 pr-2 font-semibold text-right">Public</th>
      <th class="pb-1.5 font-semibold text-right">Remplissage</th></tr></thead><tbody>${lignes}</tbody></table></div>
    <p class="text-[10.5px] text-ink/45 mt-2">Public = participants saisis, sinon présents pointés, sinon inscrits. Remplissage = inscrits / places.</p>`, 'md:col-span-2');
}

function contenuBilan(b, nomCommune) {
  const t = b.totaux, prev = b.annee_precedente || {};
  if (!t.evenements) return `<p class="text-sm text-ink/55">Aucun événement dans l'agenda en ${b.annee}.</p>`;
  const tuiles = `<div class="grid grid-cols-2 md:grid-cols-4 gap-3 md:col-span-2 min-w-0">
    ${tuile(nf(t.evenements), 'Événements', evolution(t.evenements, prev.evenements))}
    ${tuile(nf(t.public_touche), 'Personnes touchées', evolution(t.public_touche, prev.public_touche))}
    ${tuile(t.places ? `${pct(t.inscrits_jauge, t.places)} %` : '–', 'Remplissage moyen', t.complets ? `${t.complets} complet(s)` : 'Inscrits / places offertes')}
    ${tuile(nf(b.fideles), 'Habitués', `venus à 2 événements ou plus, sur ${nf(b.personnes_uniques)} usagers`)}
  </div>`;
  const types = carte('Types d\'événements', barres(b.par_type, {
    valeur: l => l.n, libelle: l => l.type,
    detail: l => `${l.n} événement${l.n > 1 ? 's' : ''} · ${nf(l.public)} pers.`,
  }));
  const mois = carte('Public par mois', colonnesMois(b.par_mois));
  const repetes = b.repetes.length ? carte('Événements répétés dans l\'année', `<ul class="flex flex-col gap-1">${b.repetes.map(r =>
    `<li class="flex justify-between text-xs"><span class="text-ink/80">${esc(r.titre)}</span><span class="text-ink/55">${r.n} fois · ${nf(r.public)} pers. au total</span></li>`).join('')}</ul>`) : '';
  return `<div class="bilan-entete hidden mb-4"><p class="text-lg font-bold">Bilan de l'agenda culturel ${b.annee}</p>
      <p class="text-xs text-ink/55">${esc(nomCommune || '')} · édité le ${new Date().toLocaleDateString('fr-FR')} avec BliGO</p></div>
    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
      ${tuiles}
      ${aRetenir(b)}
      ${carte('Public par genre', anneau(b.genre, GENRES))}
      ${carte('Public par âge', anneau(b.age, AGES))}
      ${types}
      ${mois}
      ${repetes}
      ${tableauEvenements(b.evenements)}
    </div>
    <p class="text-[10.5px] text-ink/45 mt-3">Genre et âge : public identifié (présents pointés, sinon inscrits, avec ou sans compte). Les personnes venues sans inscription comptent dans le total mais pas dans les camemberts.</p>`;
}

export async function afficherBilanAgenda({ supabase, communeId, year, container, frError, nomCommune }) {
  container.innerHTML = `<p class="text-xs text-ink/45">Chargement du bilan…</p>`;
  const { data, error } = await supabase.rpc('agenda_bilan', { p_commune_id: communeId, p_year: year });
  if (error) { container.innerHTML = `<p class="text-xs text-red-600">${esc(frError ? frError(error) : error.message)}</p>`; return; }
  dernierBilan = { data, nomCommune };
  container.innerHTML = contenuBilan(data, nomCommune);
}

export function imprimerBilanAgenda() {
  if (!dernierBilan) return;
  const zone = document.getElementById('print-bilan-area');
  zone.innerHTML = contenuBilan(dernierBilan.data, dernierBilan.nomCommune);
  zone.querySelector('.bilan-entete')?.classList.remove('hidden');
  document.body.classList.add('printing-bilan');
  const fin = () => { document.body.classList.remove('printing-bilan'); zone.innerHTML = ''; window.removeEventListener('afterprint', fin); };
  window.addEventListener('afterprint', fin);
  setTimeout(() => window.print(), 50);
}
