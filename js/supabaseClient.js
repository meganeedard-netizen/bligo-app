// Module Supabase intégré à l'appli (23/10/2026) : avant, il était
// retéléchargé depuis esm.sh à chaque changement de page (plusieurs fichiers
// en cascade), ce qui ralentissait la navigation. Refait par tailwind-build/build.sh.
import { createClient } from './vendor/supabase.js?v=2.118.0';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js?v=20261016d';

// Logiciel agent Mac/Windows (16/10/2026) : il affiche les pages de bligo.app
// et les ouvre avec « ?logiciel=1 ». Le repère reste pour toute la fenêtre
// (sessionStorage). Dans le logiciel, la connexion est gardée seulement tant
// qu'il est ouvert : il faut se reconnecter à chaque ouverture (poste partagé).
const AGENT_APP = (() => {
  try {
    if (new URLSearchParams(location.search).has('logiciel')) sessionStorage.setItem('bligo_agent_app', '1');
    return sessionStorage.getItem('bligo_agent_app') === '1';
  } catch (e) { return false; }
})();
if (AGENT_APP) window.BLIGO_AGENT_APP = true;

export const supabase = AGENT_APP
  ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { storage: window.sessionStorage, persistSession: true } })
  : createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
