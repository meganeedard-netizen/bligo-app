// Rapport annuel Néoscrib (13/11/2026)
// Enquête annuelle du ministère de la Culture (Observatoire de la lecture
// publique), relayée par la bibliothèque départementale. Formulaires 2026 :
// « rapport très abrégé » (socle minimal) et « rapport basique ».
// BliGO calcule tout ce qu'il connaît (collections en exemplaires, prêts,
// usagers, réservations, fréquentation, actions culturelles de l'agenda,
// horaires) ; le reste (surface, personnel, budget, partenariats...) se saisit
// ici une fois et reste enregistré. L'export reprend l'ordre et les codes du
// formulaire pour recopier les chiffres dans Néoscrib sans chercher.

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// ---------- Calculs à partir de neoscrib_auto ----------
// d._f_<famille>_<a|j> = [fonds, acquisitions, éliminations] ; d._p_<famille>_<a|j> = prêts
const PUB = { a: ['a'], j: ['j'], t: ['a', 'j'] };
const fonds = (fam, pub, i) => d => [].concat(fam).reduce((s, f) => s + PUB[pub].reduce((t, p) => t + ((d[`_f_${f}_${p}`] || [0, 0, 0])[i] || 0), 0), 0);
const prets = (fam, pub) => d => [].concat(fam).reduce((s, f) => s + PUB[pub].reduce((t, p) => t + (d[`_p_${f}_${p}`] || 0), 0), 0);
const TOUTES = ['livre', 'periodique', 'livre_audio', 'musique', 'video', 'jeu', 'jeu_video', 'autre'];
const AUTRES_D3 = ['jeu', 'autre'];
const ev = (types, i) => d => [].concat(types).reduce((s, t) => s + ((d[`_h_${t}`] || [0, 0])[i] || 0), 0);
const evOui = types => d => ev(types, 0)(d) > 0 ? 'Oui' : 'Non';

// Horaires saisis par jour en texte libre : « 9h-12h30 / 14h-18h », « Fermé ».
function heuresJour(txt) {
  const s = String(txt || '').toLowerCase();
  if (!s.trim() || /ferm/.test(s)) return 0;
  let total = 0;
  const re = /(\d{1,2})\s*[h:]\s*(\d{2})?\s*(?:-|–|à|a)\s*(\d{1,2})\s*[h:]?\s*(\d{2})?/g;
  let m;
  while ((m = re.exec(s))) {
    const debut = +m[1] + (+m[2] || 0) / 60, fin = +m[3] + (+m[4] || 0) / 60;
    if (fin > debut) total += fin - debut;
  }
  return total;
}
const JOURS = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
function horaires(oh) {
  let h = oh;
  if (typeof h === 'string') { try { h = JSON.parse(h); } catch { h = null; } }
  if (!h || typeof h !== 'object') return null;
  const parJour = JOURS.map(j => heuresJour(h[j]));
  if (!parJour.some(Boolean)) return null;
  const total = Math.round(parJour.reduce((a, b) => a + b, 0) * 2) / 2;
  return { heures: total, jours: parJour.filter(Boolean).length, dimanche: parJour[6] > 0 ? 'Oui' : 'Non' };
}

// ---------- Le formulaire ----------
// [code, intitulé, type (n = nombre, o = oui/non, t = texte), rapport
//  (ta = dans les deux rapports, b = rapport basique seulement), calcul]
const ON = 'o', N = 'n', T = 't';
const SECTIONS = [
  { titre: 'A1 - Site Internet', lignes: [
    ['A115', 'Site internet (adresse)', T, 'ta'],
    ['A119', 'Adresse mail principale utilisable pour les informations du Ministère', ON, 'ta'],
    ['A121', 'Attestation de conformité RGAA du site déposée', ON, 'ta'],
  ] },
  { titre: "C1 - Horaires d'ouverture, accès et installation", lignes: [
    ['C101', "Heures d'ouverture hebdomadaires tous publics", N, 'ta', d => d._horaires?.heures],
    ['C115', "Jours d'ouverture hebdomadaires", N, 'ta', d => d._horaires?.jours],
    ['C102', "Jours d'ouverture annuels", N, 'b'],
    ['C116', 'Ouverte le dimanche', ON, 'ta', d => d._horaires?.dimanche],
    ['C103', 'Places assises', N, 'b'],
    ['C106', 'Postes informatiques publics avec accès internet', N, 'ta'],
    ['C120', 'Connexion wifi publique', ON, 'ta'],
    ['C108', 'Postes informatiques professionnels avec accès internet', N, 'ta'],
    ['C110', 'Imprimantes en accès public', N, 'b'],
    ['C117', 'Tablettes mises à disposition du public', N, 'b'],
    ['C118', 'Liseuses mises à disposition du public', N, 'b'],
  ] },
  { titre: 'C2 - Catalogue', lignes: [
    ['C201', 'Catalogue informatisé', ON, 'b', d => d.C201],
    ['C202', 'Nombre total de notices au catalogue (fonds propre)', N, 'b', d => d.C202],
    ['C206', 'Nom du logiciel SIGB', T, 'b', d => d.C206],
  ] },
  { titre: 'C3 - Locaux', lignes: [
    ['C301', 'Surface utile nette totale (m²)', N, 'ta'],
    ['C309', 'Bâtiment accessible (loi du 11 février 2005)', ON, 'ta'],
  ] },
  { titre: 'D1 - Livres imprimés (exemplaires)', lignes: [
    ['D101', 'Fonds adulte', N, 'ta', fonds('livre', 'a', 0)],
    ['D116', 'Fonds jeunesse', N, 'ta', fonds('livre', 'j', 0)],
    ['D128', 'Fonds total', N, 'ta', fonds('livre', 't', 0)],
    ['D102', 'Acquisitions adulte', N, 'b', fonds('livre', 'a', 1)],
    ['D117', 'Acquisitions jeunesse', N, 'b', fonds('livre', 'j', 1)],
    ['D129', 'Acquisitions total', N, 'b', fonds('livre', 't', 1)],
    ['D103', 'Éliminations adulte', N, 'b', fonds('livre', 'a', 2)],
    ['D118', 'Éliminations jeunesse', N, 'b', fonds('livre', 'j', 2)],
    ['D130', 'Éliminations total', N, 'b', fonds('livre', 't', 2)],
    ['D131', 'Dont nombre de dons', N, 'b'],
    ['D144', 'En dépôt de la BD au 31/12 de l\'année précédente : adulte', N, 'ta'],
    ['D142', 'En dépôt de la BD : jeunesse', N, 'ta'],
    ['D143', 'En dépôt de la BD : total', N, 'ta'],
  ] },
  { titre: 'D2 - Publications en série (abonnements)', note: 'Calculé à partir des titres de type Périodique au catalogue : vérifie que chacun correspond bien à un abonnement en cours.', lignes: [
    ['D201', 'Abonnements adultes', N, 'b', d => d._abos_a],
    ['D203', 'Abonnements jeunesse', N, 'b', d => d._abos_j],
    ['D211', 'Abonnements total', N, 'b', d => (d._abos_a || 0) + (d._abos_j || 0)],
  ] },
  { titre: 'D3 - Autres documents', lignes: [
    ['D331', 'La bibliothèque possède d\'autres types de documents', ON, 'b', d => fonds(AUTRES_D3, 't', 0)(d) > 0 ? 'Oui' : 'Non'],
    ['D332', 'Jeux de société : fonds', N, 'b', fonds('jeu', 't', 0)],
    ['D333', 'Jeux de société : acquisitions', N, 'b', fonds('jeu', 't', 1)],
    ['D321', 'Total autres documents : fonds', N, 'b', fonds(AUTRES_D3, 't', 0)],
    ['D322', 'Total autres documents : acquisitions', N, 'b', fonds(AUTRES_D3, 't', 1)],
    ['D320', 'Total autres documents : éliminations', N, 'b', fonds(AUTRES_D3, 't', 2)],
  ] },
  { titre: 'D4 - Documents audiovisuels sur support', lignes: [
    ['D450', 'Fonds de CD ou de DVD', ON, 'b', d => fonds(['musique', 'livre_audio', 'video'], 't', 0)(d) > 0 ? 'Oui' : 'Non'],
    ['D401', 'Musique : fonds', N, 'b', fonds('musique', 't', 0)],
    ['D402', 'Musique : acquisitions', N, 'b', fonds('musique', 't', 1)],
    ['D416', 'Musique : éliminations', N, 'b', fonds('musique', 't', 2)],
    ['D423', 'Livres enregistrés adultes : fonds', N, 'b', fonds('livre_audio', 'a', 0)],
    ['D424', 'Livres enregistrés adultes : acquisitions', N, 'b', fonds('livre_audio', 'a', 1)],
    ['D425', 'Livres enregistrés adultes : éliminations', N, 'b', fonds('livre_audio', 'a', 2)],
    ['D435', 'Livres enregistrés jeunesse : fonds', N, 'b', fonds('livre_audio', 'j', 0)],
    ['D436', 'Livres enregistrés jeunesse : acquisitions', N, 'b', fonds('livre_audio', 'j', 1)],
    ['D437', 'Livres enregistrés jeunesse : éliminations', N, 'b', fonds('livre_audio', 'j', 2)],
    ['D405', 'Total livres enregistrés : fonds', N, 'b', fonds('livre_audio', 't', 0)],
    ['D406', 'Total livres enregistrés : acquisitions', N, 'b', fonds('livre_audio', 't', 1)],
    ['D417', 'Total livres enregistrés : éliminations', N, 'b', fonds('livre_audio', 't', 2)],
    ['D409', 'Total documents sonores : fonds', N, 'b', fonds(['musique', 'livre_audio'], 't', 0)],
    ['D410', 'Total documents sonores : acquisitions', N, 'b', fonds(['musique', 'livre_audio'], 't', 1)],
    ['D418', 'Total documents sonores : éliminations', N, 'b', fonds(['musique', 'livre_audio'], 't', 2)],
    ['D429', 'Vidéo adultes : fonds', N, 'b', fonds('video', 'a', 0)],
    ['D430', 'Vidéo adultes : acquisitions', N, 'b', fonds('video', 'a', 1)],
    ['D431', 'Vidéo adultes : éliminations', N, 'b', fonds('video', 'a', 2)],
    ['D441', 'Vidéo jeunesse : fonds', N, 'b', fonds('video', 'j', 0)],
    ['D442', 'Vidéo jeunesse : acquisitions', N, 'b', fonds('video', 'j', 1)],
    ['D443', 'Vidéo jeunesse : éliminations', N, 'b', fonds('video', 'j', 2)],
    ['D411', 'Total vidéo : fonds', N, 'b', fonds('video', 't', 0)],
    ['D412', 'Total vidéo : acquisitions', N, 'b', fonds('video', 't', 1)],
    ['D419', 'Total vidéo : éliminations', N, 'b', fonds('video', 't', 2)],
    ['D444', 'Jeux vidéo : fonds', N, 'b', fonds('jeu_video', 't', 0)],
    ['D445', 'Jeux vidéo : acquisitions', N, 'b', fonds('jeu_video', 't', 1)],
    ['D446', 'Jeux vidéo : éliminations', N, 'b', fonds('jeu_video', 't', 2)],
  ] },
  { titre: 'E1 - Usagers', note: "BliGO ne demande ni l'âge ni le sexe des usagers (RGPD) : la répartition par âge est à saisir à la main, si tu la connais.", lignes: [
    ['E101', 'Inscrits actifs (total)', N, 'b', d => d.E101],
    ['E102', 'Dont nouveaux inscrits', N, 'b', d => d.E102],
    ['E112', 'Emprunteurs actifs : enfants (0-14 ans)', N, 'ta'],
    ['E121', 'Emprunteurs actifs : adultes (15-64 ans)', N, 'ta'],
    ['E130', 'Emprunteurs actifs : adultes (65 ans et plus)', N, 'ta'],
    ['E139', 'Emprunteurs actifs : total adulte', N, 'ta'],
    ['E103', 'Emprunteurs actifs : total (enfants et adultes)', N, 'ta', d => d.E103],
    ['E142', 'Dont résidents de la commune ou du réseau', N, 'ta'],
    ['E144', 'Collectivités emprunteuses', N, 'ta'],
    ['E147', 'Fréquentation annuelle (entrées)', N, 'ta', d => d.E147],
    ['E160', 'Semaine test 1', N, 'ta'],
    ['E161', 'Semaine test 2', N, 'ta'],
  ] },
  { titre: 'E2 - Prêts', lignes: [
    ['E201', 'Livres : adultes', N, 'ta', prets('livre', 'a')],
    ['E202', 'Livres : jeunesse', N, 'ta', prets('livre', 'j')],
    ['E203', 'Livres : total', N, 'ta', prets('livre', 't')],
    ['E241', 'Dont prêts sur documents de la BD', N, 'ta'],
    ['E205', 'Publications en série : adultes', N, 'b', prets('periodique', 'a')],
    ['E206', 'Publications en série : jeunesse', N, 'b', prets('periodique', 'j')],
    ['E207', 'Publications en série : total', N, 'b', prets('periodique', 't')],
    ['E211', 'Documents sonores, musique : total', N, 'b', prets('musique', 't')],
    ['E213', 'Livres enregistrés : adultes', N, 'b', prets('livre_audio', 'a')],
    ['E214', 'Livres enregistrés : jeunesse', N, 'b', prets('livre_audio', 'j')],
    ['E215', 'Livres enregistrés : total', N, 'b', prets('livre_audio', 't')],
    ['E235', 'Documents sonores : total', N, 'b', prets(['musique', 'livre_audio'], 't')],
    ['E217', 'Vidéo : adultes', N, 'b', prets('video', 'a')],
    ['E218', 'Vidéo : jeunesse', N, 'b', prets('video', 'j')],
    ['E219', 'Vidéo : total', N, 'b', prets('video', 't')],
    ['E247', 'Jeux de société', N, 'b', prets('jeu', 't')],
    ['E248', 'Jeux vidéo', N, 'b', prets('jeu_video', 't')],
    ['E221', 'Autres documents : adultes', N, 'b', prets('autre', 'a')],
    ['E222', 'Autres documents : jeunesse', N, 'b', prets('autre', 'j')],
    ['E223', 'Autres documents : total', N, 'b', prets('autre', 't')],
    ['E237', 'Total des prêts : adultes', N, 'ta', prets(TOUTES, 'a')],
    ['E238', 'Total des prêts : jeunesse', N, 'ta', prets(TOUTES, 'j')],
    ['E239', 'Total des prêts', N, 'ta', prets(TOUTES, 't')],
    ['E240', 'Dont prêts aux collectivités', N, 'ta'],
  ] },
  { titre: "E3 et E5 - Autres usages, services en ligne", lignes: [
    ['E302', 'Réservations', N, 'b', d => d.E302],
    ['E504', 'Catalogue en ligne', ON, 'b', d => d.E504],
    ['E541', 'Réseaux sociaux', ON, 'b'],
    ['E542', 'Lesquels ?', T, 'b'],
  ] },
  { titre: 'F - Budget (€)', note: 'À demander au service finances de la commune.', lignes: [
    ['F701', 'Dépenses d\'acquisition : livres imprimés', N, 'ta'],
    ['F714', 'Total des dépenses d\'acquisition de documents', N, 'ta'],
    ['F101', 'Total des dépenses d\'investissement', N, 'b'],
    ['F201', 'Dépenses de personnel salarié', N, 'b'],
    ['F314', 'Dépenses d\'acquisitions documentaires (fonctionnement)', N, 'b'],
    ['F502', 'Dépenses d\'action culturelle', N, 'b'],
    ['F504', 'Dépenses informatiques', N, 'b'],
    ['F508', 'Dépenses de communication', N, 'b'],
    ['F603', 'Recettes propres', N, 'b'],
    ['F604', 'Dont droits d\'inscription', N, 'b'],
  ] },
  { titre: 'G - Personnel', note: 'ETP = équivalent temps plein (un mi-temps = 0,5).', lignes: [
    ['G143', 'La bibliothèque emploie du personnel salarié', ON, 'ta'],
    ['G151', 'Catégorie C : titulaires (personnes)', N, 'ta'],
    ['G152', 'Catégorie C : contractuels (personnes)', N, 'ta'],
    ['G153', 'Catégorie C : total en ETP', N, 'ta'],
    ['G154', 'Dont catégorie C qualifié', N, 'ta'],
    ['G145', 'Catégorie A / A+ : titulaires (personnes)', N, 'b'],
    ['G146', 'Catégorie A / A+ : contractuels (personnes)', N, 'b'],
    ['G147', 'Catégorie A / A+ : total en ETP', N, 'b'],
    ['G148', 'Catégorie B : titulaires (personnes)', N, 'b'],
    ['G149', 'Catégorie B : contractuels (personnes)', N, 'b'],
    ['G150', 'Catégorie B : total en ETP', N, 'b'],
    ['G135', 'Total salariés (personnes)', N, 'ta'],
    ['G102', 'Total salariés (ETP)', N, 'ta'],
    ['G120', 'Hors filière culturelle, catégorie C (personnes)', N, 'ta'],
    ['G121', 'Hors filière culturelle, catégorie C (ETP)', N, 'ta'],
    ['G144', 'La bibliothèque accueille des bénévoles', ON, 'ta'],
    ['G129', 'Bénévoles (personnes)', N, 'ta'],
    ['G130', 'Dont bénévoles qualifiés', N, 'ta'],
    ['G131', 'Bénévoles (ETP)', N, 'ta'],
    ['G101', 'Nombre total de postes (personnes)', N, 'ta'],
    ['G132', 'Nombre total de postes (ETP)', N, 'ta'],
  ] },
  { titre: 'H1 - Partenariats avec des institutions', lignes: [
    ['H101', 'Partenariat avec des écoles', ON, 'ta'],
    ['H102', 'Écoles : nombre de classes', N, 'b'],
    ['H130', 'Écoles : nombre d\'accueils de classes', N, 'b'],
    ['H103', 'Écoles : population touchée (estimation)', N, 'b'],
    ['H104', 'Partenariat avec des collèges', ON, 'b'],
    ['H106', 'Collèges : population touchée (estimation)', N, 'b'],
    ['H116', 'Partenariat avec des maisons de retraite', ON, 'b'],
    ['H117', 'Maisons de retraite : population touchée', N, 'b'],
    ['H120', 'Partenariat avec des centres de loisirs', ON, 'b'],
    ['H121', 'Centres de loisirs : population touchée', N, 'b'],
    ['H122', 'Partenariat avec des services de la petite enfance', ON, 'b'],
    ['H123', 'Petite enfance : population touchée', N, 'b'],
  ] },
  { titre: "H4 - Actions au sein de l'établissement (agenda BliGO)", note: "Compté à partir de l'agenda de l'année. Si ton agenda contient aussi des événements qui ne sont pas organisés par la médiathèque (auditorium, autres services), corrige les chiffres. Population touchée = présents pointés, sinon inscrits.", lignes: [
    ['H401', 'Expositions', ON, 'b', evOui('Exposition')],
    ['H402', 'Expositions : nombre (tous publics)', N, 'b', ev('Exposition', 0)],
    ['H409', 'Conférences, rencontres, lectures', ON, 'b', evOui(['Conférence', 'Débat'])],
    ['H410', 'Conférences, rencontres, lectures : nombre (tous publics)', N, 'b', ev(['Conférence', 'Débat'], 0)],
    ['H412', 'Conférences, rencontres, lectures : population touchée', N, 'b', ev(['Conférence', 'Débat'], 1)],
    ['H417', 'Séances de conte', ON, 'b', evOui('Heure du conte')],
    ['H418', 'Séances de conte : nombre (enfants)', N, 'b', ev('Heure du conte', 0)],
    ['H419', 'Séances de conte : population touchée', N, 'b', ev('Heure du conte', 1)],
    ['H437', 'Concerts', ON, 'b', evOui('Concert')],
    ['H438', 'Concerts : nombre (tous publics)', N, 'b', ev('Concert', 0)],
    ['H440', 'Concerts : population touchée', N, 'b', ev('Concert', 1)],
    ['H441', 'Projections', ON, 'b', evOui('Cinéma')],
    ['H442', 'Projections : nombre (tous publics)', N, 'b', ev('Cinéma', 0)],
    ['H444', 'Projections : population touchée', N, 'b', ev('Cinéma', 1)],
    ['H445', 'Clubs de lecteurs', ON, 'b', evOui('Club de lecture')],
    ['H446', 'Clubs de lecteurs : nombre de séances (tous publics)', N, 'b', ev('Club de lecture', 0)],
    ['H448', 'Clubs de lecteurs : population touchée', N, 'b', ev('Club de lecture', 1)],
    ['H461', 'Ateliers', ON, 'b', evOui('Atelier')],
    ['H462', 'Ateliers : nombre (tous publics)', N, 'b', ev('Atelier', 0)],
    ['H464', 'Ateliers : population touchée', N, 'b', ev('Atelier', 1)],
    ['H428', 'Autres actions (spectacles, théâtre, autres)', ON, 'b', evOui(['Théâtre', 'Spectacle', 'Autre'])],
    ['H429', 'Autres actions : nombre (tous publics)', N, 'b', ev(['Théâtre', 'Spectacle', 'Autre'], 0)],
  ] },
  { titre: "H5 - Actions hors de l'établissement", lignes: [
    ['H501', 'Actions hors les murs', ON, 'b'],
    ['H502', 'Actions hors les murs : nombre', N, 'b'],
    ['H504', 'Portage à domicile', ON, 'ta'],
    ['H505', 'Portage à domicile : nombre d\'actions', N, 'ta'],
    ['H506', 'Portage à domicile : population touchée', N, 'ta'],
  ] },
  { titre: 'J - Données locales', lignes: [
    ['J201', 'Inscription et prêt gratuits pour tous les usagers', ON, 'ta', d => d._gratuit],
    ['J601', 'Local spécifique pour la bibliothèque', ON, 'ta'],
  ] },
];

// ---------- Données ----------
async function charger(supabase, communeId, year) {
  const [auto, saisies, commune] = await Promise.all([
    supabase.rpc('neoscrib_auto', { p_commune_id: communeId, p_year: year }),
    supabase.from('neoscrib_saisies').select('code, valeur').eq('commune_id', communeId).eq('annee', year),
    supabase.from('communes').select('opening_hours, tariff_mineur_cents, tariff_majeur_cents').eq('id', communeId).maybeSingle(),
  ]);
  if (auto.error) throw auto.error;
  if (saisies.error) throw saisies.error;
  const d = auto.data || {};
  d._horaires = horaires(commune.data?.opening_hours);
  const c = commune.data;
  if (c && c.tariff_mineur_cents != null) d._gratuit = (c.tariff_mineur_cents || 0) + (c.tariff_majeur_cents || 0) === 0 ? 'Oui' : 'Non';
  const s = {};
  (saisies.data || []).forEach(r => { s[r.code] = r.valeur; });
  return { d, s };
}

// Valeur finale d'une ligne + son origine
function valeur([code, , , , calc], d, s) {
  if (s[code] != null && s[code] !== '') return { v: s[code], o: calc ? 'Corrigé' : 'Saisi' };
  if (calc) {
    const v = calc(d);
    if (v != null && v !== '') return { v, o: 'Calculé par BliGO' };
  }
  return { v: '', o: 'À compléter' };
}

const lignesDu = rapport => SECTIONS.map(sec => ({ ...sec, lignes: sec.lignes.filter(l => rapport === 'b' || l[3] === 'ta') }))
  .filter(sec => sec.lignes.length);

// ---------- Écran ----------
export async function afficherNeoscrib({ supabase, communeId, year, rapport, container, frError }) {
  container.innerHTML = `<p class="text-sm text-ink/40 text-center py-8">Calcul en cours…</p>`;
  let donnees;
  try { donnees = await charger(supabase, communeId, year); }
  catch (e) { container.innerHTML = `<p class="text-sm text-red-600">Erreur : ${esc(frError ? frError(e) : e.message)}</p>`; return; }
  const { d, s } = donnees;
  const sections = lignesDu(rapport);
  const toutes = sections.flatMap(x => x.lignes);
  const remplies = toutes.filter(l => valeur(l, d, s).v !== '').length;
  const auto = toutes.filter(l => valeur(l, d, s).o === 'Calculé par BliGO').length;

  const champ = l => {
    const [code, label, type, , calc] = l;
    const { v, o } = valeur(l, d, s);
    const auto = o === 'Calculé par BliGO', corrige = o === 'Corrigé';
    const base = `data-neo-code="${code}" class="neo-input w-full border rounded-lg px-2 py-1.5 text-sm text-right ${auto ? 'border-transparent bg-mango-50 font-bold text-ink' : corrige ? 'border-hibiscus-200 bg-white font-bold' : 'border-mango-100 bg-white'}"`;
    const input = type === ON
      ? `<select ${base}><option value=""></option>${['Oui', 'Non'].map(x => `<option ${v === x ? 'selected' : ''}>${x}</option>`).join('')}</select>`
      : `<input ${base} ${type === N ? 'inputmode="decimal"' : ''} value="${esc(v)}" placeholder="${type === T ? 'à saisir' : '-'}">`;
    const tag = auto ? '<span class="text-[9.5px] font-bold text-mango-700">auto</span>'
      : corrige ? `<button type="button" data-neo-reset="${code}" title="Revenir au chiffre calculé" class="text-[9.5px] font-bold text-hibiscus-700 underline">corrigé ↺</button>`
      : calc ? '' : '';
    return `
      <div class="grid grid-cols-[1fr_110px_52px] gap-2 px-4 py-1.5 items-center border-t border-mango-50 text-sm">
        <span class="text-ink/80 leading-snug">${esc(label)}</span>
        <span>${input}</span>
        <span class="text-right"><span class="block text-[10px] text-ink/40 font-mono">${code}</span>${tag}</span>
      </div>`;
  };

  container.innerHTML = `
    <div class="bg-white border border-mango-100 rounded-xl p-4 text-sm text-ink/70">
      <p><b class="text-ink">${remplies} champs remplis sur ${toutes.length}</b>, dont ${auto} calculés automatiquement par BliGO.</p>
      <p class="text-xs text-ink/50 mt-1">Les champs « auto » viennent de tes données (catalogue en exemplaires, prêts de l'appli et du comptoir, réservations, fréquentation, agenda, horaires). Tu peux les corriger. Le reste se saisit une fois : c'est enregistré tout seul.${d.E103_anonymes ? ` Attention : ${d.E103_anonymes} prêt(s) de l'année ont déjà été anonymisés, leurs emprunteurs ne sont plus comptés dans E103.` : ''}</p>
    </div>
    ${sections.map(sec => `
      <div class="bg-white border border-mango-100 rounded-xl shadow-sm overflow-hidden">
        <div class="px-4 py-2.5 bg-mango-50 text-[11px] font-bold uppercase tracking-wide text-ink/50">${esc(sec.titre)}</div>
        ${sec.note ? `<p class="px-4 py-2 text-[11.5px] text-ink/50">${esc(sec.note)}</p>` : ''}
        ${sec.lignes.map(champ).join('')}
      </div>`).join('')}
    <p class="text-[11px] text-ink/40">Ces chiffres préparent ta saisie sur neoscrib.culture.gouv.fr (identifiants donnés par ta bibliothèque départementale). L'export reprend les codes dans l'ordre du formulaire.</p>`;

  const enregistrer = async (code, val) => {
    const v = String(val ?? '').trim();
    const r = v === ''
      ? await supabase.from('neoscrib_saisies').delete().eq('commune_id', communeId).eq('annee', year).eq('code', code)
      : await supabase.from('neoscrib_saisies').upsert({ commune_id: communeId, annee: year, code, valeur: v, updated_at: new Date().toISOString() });
    if (r.error) { alert('Erreur : ' + (frError ? frError(r.error) : r.error.message)); return false; }
    return true;
  };
  container.querySelectorAll('.neo-input').forEach(el => {
    el.addEventListener('change', async () => {
      const code = el.dataset.neoCode;
      const ligne = toutes.find(l => l[0] === code);
      const calc = ligne[4] ? ligne[4](d) : null;
      // Retaper le chiffre calculé = pas de correction.
      const val = calc != null && String(calc) === el.value.trim() ? '' : el.value;
      if (await enregistrer(code, val)) afficherNeoscrib({ supabase, communeId, year, rapport, container, frError });
    });
  });
  container.querySelectorAll('[data-neo-reset]').forEach(b => b.addEventListener('click', async () => {
    if (await enregistrer(b.dataset.neoReset, '')) afficherNeoscrib({ supabase, communeId, year, rapport, container, frError });
  }));
}

// ---------- Export (lignes pour un CSV) ----------
export async function lignesNeoscrib({ supabase, communeId, year, rapport = 'b' }) {
  const { d, s } = await charger(supabase, communeId, year);
  const rows = [[`Rapport Néoscrib ${year} (${rapport === 'b' ? 'rapport basique' : 'rapport très abrégé'})`, '', '', ''], ['Code', 'Indicateur', 'Valeur', 'Origine']];
  lignesDu(rapport).forEach(sec => {
    rows.push(['', '', '', ''], [sec.titre, '', '', '']);
    sec.lignes.forEach(l => { const { v, o } = valeur(l, d, s); rows.push([l[0], l[1], v, o]); });
  });
  return rows;
}
