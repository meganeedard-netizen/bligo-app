import { supabase } from './supabaseClient.js?v=20261023';

// « Continuer avec Apple » et « Continuer avec Google » (02/11/2026).
// iPhone : Apple + Google ; Android : Google ; site bligo.app : Google.
// Dans l'appli, le module natif BligoConnexion (ConnexionPlugin.swift /
// ConnexionPlugin.java) renvoie le jeton d'identité, donné ensuite à
// Supabase. Sur le site, Google passe par la page de connexion de Google.
// Un compte créé ainsi est rattaché à la médiathèque choisie sur l'écran
// d'accueil (sql/connexion_google_apple_2026-11-02.sql).

const platform = () => (window.Capacitor?.isNativePlatform?.() ? window.Capacitor.getPlatform() : 'web');
const plugin = () => window.Capacitor?.Plugins?.BligoConnexion || null;

export function socialProviders() {
  if (window.BLIGO_AGENT_APP) return [];
  const p = platform();
  if (p === 'web') return ['google'];
  if (!plugin()) return [];
  return p === 'ios' ? ['apple', 'google'] : ['google'];
}

async function sha256Hex(text) {
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(hash)].map(b => b.toString(16).padStart(2, '0')).join('');
}

function randomNonce() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
}

const PENDING_KEY = 'bligo_social_commune';

// Renvoie { cancelled }, { error }, { redirect } (site) ou { ok, isNew }.
export async function signInWith(provider, communeId) {
  if (platform() === 'web') {
    try { localStorage.setItem(PENDING_KEY, communeId || ''); } catch (e) {}
    const { error } = await supabase.auth.signInWithOAuth({
      provider,
      options: { redirectTo: `${location.origin}/index.html?social=1` },
    });
    return error ? { error } : { redirect: true };
  }
  // Le jeton porte l'empreinte du nonce, Supabase la compare au nonce lui-même.
  const nonce = randomNonce();
  let res;
  try {
    res = await plugin()[provider]({ nonce: await sha256Hex(nonce) });
  } catch (error) {
    // Erreurs du téléphone (en anglais) : message à nous.
    return { error: { message: error?.code === 'NO_ACCOUNT'
      ? "Aucun compte Google n'est enregistré sur ce téléphone. Ajoute-le dans les réglages, ou connecte-toi avec ton e-mail."
      : `Connexion ${provider === 'apple' ? 'Apple' : 'Google'} impossible. Réessaie ou connecte-toi avec ton e-mail.` } };
  }
  if (res?.cancelled) return { cancelled: true };
  const { error } = await supabase.auth.signInWithIdToken({ provider, token: res.idToken, nonce });
  if (error) return { error };
  const fullName = [res.givenName, res.familyName].filter(Boolean).join(' ');
  return { ok: true, isNew: await finishSocialSignIn(communeId, fullName) };
}

// Retour sur le site après la page de connexion de Google (?social=1).
export async function finishWebSocialSignIn() {
  let communeId = null;
  try { communeId = localStorage.getItem(PENDING_KEY); localStorage.removeItem(PENDING_KEY); } catch (e) {}
  return finishSocialSignIn(communeId, '');
}

// Après la connexion : médiathèque (nouveau compte), prénom et nom donnés par
// Apple (seulement à la première connexion), adresse e-mail vérifiée.
// Renvoie true si le compte vient d'être créé.
async function finishSocialSignIn(communeId, fullName) {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return false;
  let isNew = false;
  if (communeId) {
    const { data } = await supabase.rpc('rattacher_ma_mediatheque', { p_commune_id: Number(communeId) });
    isNew = data === true;
  }
  const { data: profile } = await supabase.from('profiles').select('full_name, email_verifie').eq('id', session.user.id).maybeSingle();
  if (fullName && (!profile?.full_name || profile.full_name === 'Nouvel usager')) {
    await supabase.from('profiles').update({ full_name: fullName }).eq('id', session.user.id);
  }
  // Compte e-mail + mot de passe déjà existant, pas encore vérifié : la
  // connexion Google/Apple avec la même adresse le vérifie.
  if (profile && !profile.email_verifie) await supabase.rpc('confirmer_mon_email');
  return isNew;
}
