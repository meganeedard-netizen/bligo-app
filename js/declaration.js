// Majeur / mineur, âge du mineur et carte famille (25/11/2026, demande de
// Mégane). Même bloc à l'inscription et dans le profil. Âges seulement :
// ni date de naissance, ni prénom des enfants.
const CLE = 'bligo_declaration';

export function ageActuel(age, depuis) {
  if (age == null) return null;
  if (!depuis) return Number(age);
  const d = new Date(depuis + 'T00:00:00'), n = new Date();
  let ans = n.getFullYear() - d.getFullYear();
  if (n.getMonth() < d.getMonth() || (n.getMonth() === d.getMonth() && n.getDate() < d.getDate())) ans--;
  return Number(age) + Math.max(0, ans);
}
export const libelleAge = a => a === 0 ? 'moins d\'1 an' : `${a} an${a > 1 ? 's' : ''}`;

// Texte court, aussi utilisé par le logiciel (« 2 adultes, 2 enfants : 6 ans, 9 ans »).
export function resume(p) {
  if (p?.tariff_category === 'mineur' && p.declared_age != null) return `Mineur, ${libelleAge(ageActuel(p.declared_age, p.declared_on))}`;
  if (p?.tariff_category === 'famille' && p.family_adults) {
    const e = (p.family_children || []).map(a => ageActuel(a, p.declared_on));
    return `${p.family_adults} adulte${p.family_adults > 1 ? 's' : ''}, ${e.length} enfant${e.length > 1 ? 's' : ''} : ${e.map(a => a >= 18 ? '18 ans et plus' : libelleAge(a)).join(', ')}`;
  }
  return '';
}

export function monter(box, depart = {}) {
  const etat = {
    cat: depart.tariff_category === 'mineur' ? 'mineur' : depart.tariff_category ? 'majeur' : null,
    age: depart.declared_age ?? null,
    famille: depart.tariff_category === 'famille',
    adultes: depart.family_adults || 1,
    enfants: depart.family_children?.length ? depart.family_children.map(a => Math.min(17, ageActuel(a, depart.declared_on))) : [null],
  };
  const champ = 'w-full bg-[#EEEDF2] rounded-xl px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-mango-300';
  const bouton = on => `flex-1 rounded-xl py-3 text-sm font-semibold border ${on ? 'bg-brand text-white border-brand' : 'bg-white text-ink/60 border-mango-100'}`;
  const ages = v => `<option value="" ${v == null ? 'selected' : ''} disabled>Âge</option>` +
    Array.from({ length: 18 }, (_, a) => `<option value="${a}" ${v === a ? 'selected' : ''}>${libelleAge(a)}</option>`).join('');
  function dessiner() {
    box.innerHTML = `
      <div class="flex gap-2 mb-2">
        <button type="button" data-cat="majeur" aria-pressed="${etat.cat === 'majeur'}" class="${bouton(etat.cat === 'majeur')}">Majeur</button>
        <button type="button" data-cat="mineur" aria-pressed="${etat.cat === 'mineur'}" class="${bouton(etat.cat === 'mineur')}">Mineur</button>
      </div>
      ${etat.cat === 'mineur' ? `<label class="text-xs font-semibold text-ink/60 block mb-1">Ton âge</label><select data-age class="${champ}">${ages(etat.age)}</select>` : ''}
      ${etat.cat === 'majeur' ? `
        <label class="flex items-center justify-between gap-3 py-2 text-sm font-semibold text-ink cursor-pointer">
          <span>Carte famille<span class="block text-xs font-normal text-ink/50">Un seul compte pour toute la famille</span></span>
          <input type="checkbox" data-famille ${etat.famille ? 'checked' : ''} class="accent-mango-600 w-5 h-5 shrink-0">
        </label>
        ${etat.famille ? `
          <div class="grid grid-cols-2 gap-2 mb-2">
            <div><label class="text-xs font-semibold text-ink/60 block mb-1">Adultes</label>
              <select data-adultes class="${champ}">${[1, 2].map(n => `<option ${etat.adultes === n ? 'selected' : ''}>${n}</option>`).join('')}</select></div>
            <div><label class="text-xs font-semibold text-ink/60 block mb-1">Enfants</label>
              <select data-nb class="${champ}">${Array.from({ length: 10 }, (_, i) => `<option ${etat.enfants.length === i + 1 ? 'selected' : ''}>${i + 1}</option>`).join('')}</select></div>
          </div>
          <div class="grid grid-cols-2 gap-2">${etat.enfants.map((a, i) => `<div><label class="text-xs font-semibold text-ink/60 block mb-1">Enfant ${i + 1}</label><select data-enfant="${i}" class="${champ}">${ages(a)}</select></div>`).join('')}</div>` : ''}` : ''}`;
    box.querySelectorAll('[data-cat]').forEach(b => b.onclick = () => { etat.cat = b.dataset.cat; dessiner(); });
    const sur = (s, f) => { const el = box.querySelector(s); if (el) el.onchange = () => f(el); };
    sur('[data-age]', el => { etat.age = Number(el.value); });
    sur('[data-famille]', el => { etat.famille = el.checked; dessiner(); });
    sur('[data-adultes]', el => { etat.adultes = Number(el.value); });
    sur('[data-nb]', el => { const n = Number(el.value); etat.enfants = Array.from({ length: n }, (_, i) => etat.enfants[i] ?? null); dessiner(); });
    box.querySelectorAll('[data-enfant]').forEach(el => el.onchange = () => { etat.enfants[Number(el.dataset.enfant)] = Number(el.value); });
  }
  dessiner();
  return {
    // { erreur } ou les paramètres de declare_my_profile.
    lire() {
      if (!etat.cat) return { erreur: 'Indique si tu es majeur ou mineur.' };
      if (etat.cat === 'mineur') return etat.age == null ? { erreur: 'Indique ton âge.' } : { valeur: { p_category: 'mineur', p_age: etat.age, p_adults: null, p_children: null } };
      if (!etat.famille) return { valeur: { p_category: 'majeur', p_age: null, p_adults: null, p_children: null } };
      if (etat.enfants.some(a => a == null)) return { erreur: 'Indique l\'âge de chaque enfant.' };
      return { valeur: { p_category: 'famille', p_age: null, p_adults: etat.adultes, p_children: [...etat.enfants] } };
    },
  };
}

export const envoyer = (supabase, valeur) => supabase.rpc('declare_my_profile', valeur);

// Inscription sans session ouverte tout de suite : envoyé à la 1re connexion,
// seulement pour l'adresse qui l'a saisi.
export function garder(email, valeur) { try { localStorage.setItem(CLE, JSON.stringify({ email: email.toLowerCase(), valeur })); } catch {} }
export async function envoyerEnAttente(supabase, user) {
  let d = null;
  try { d = JSON.parse(localStorage.getItem(CLE) || 'null'); } catch {}
  if (!d || !user?.email || d.email !== user.email.toLowerCase()) return;
  const { error } = await envoyer(supabase, d.valeur);
  if (!error || !/fetch|network/i.test(error.message)) { try { localStorage.removeItem(CLE); } catch {} }
}
