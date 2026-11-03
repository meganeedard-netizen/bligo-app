// Module Supabase intégré à l'appli (23/10/2026) : avant, il était
// retéléchargé depuis esm.sh à chaque changement de page (plusieurs fichiers
// en cascade), ce qui ralentissait la navigation. Refait par tailwind-build/build.sh.
import { createClient } from './vendor/supabase.js?v=2.118.0';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js?v=20261016d';
import { offlineFetch, keepSessionOffline } from './horsConnexion.js?v=20261103a';

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

// Mode hors connexion (03/11/2026) : appli usager seulement. Le logiciel des
// agents (admin, super-admin) travaille toujours sur les données du moment.
const AGENT_PAGE = /(^|\/)(admin|superadmin)\.html$/.test(location.pathname);

export const supabase = AGENT_APP
  ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { storage: window.sessionStorage, persistSession: true } })
  : AGENT_PAGE
    ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
    : createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { fetch: offlineFetch(SUPABASE_URL) } });
if (!AGENT_APP && !AGENT_PAGE) keepSessionOffline(supabase);
