// Mode hors connexion de l'appli usager (03/11/2026, demande de Mégane).
// Chaque lecture faite auprès de Supabase (catalogue, emprunts, réservations,
// points, agenda, profil…) est gardée sur le téléphone. Sans réseau, ou
// quand le réseau est trop lent, l'appli réaffiche ces dernières données
// avec un bandeau « Hors connexion : infos du JJ/MM à HHh ».
// Les actions (commander, s'inscrire, prolonger…) ne sont jamais rejouées
// plus tard : sans réseau, elles répondent « Pas de réseau, réessaie quand
// tu seras connecté », pour que l'usager sache que rien n'est parti.

const DB_NAME = 'bligo-hors-connexion';
const STORE = 'reponses';
const SLOW_MS = 6000;              // au-delà, on montre les données gardées
const MAX_AGE = 30 * 24 * 3600 * 1000;
// Fonctions de lecture seule appelées en POST (les autres RPC sont des actions).
const READ_RPC = /\/rest\/v1\/rpc\/(my_holds|family_usage)(\?|$)/;
export const OFFLINE_MESSAGE = 'Pas de réseau, réessaie quand tu seras connecté.';

let dbPromise = null;
function db() {
  if (!dbPromise) {
    dbPromise = new Promise((resolve) => {
      try {
        const req = indexedDB.open(DB_NAME, 1);
        req.onupgradeneeded = () => req.result.createObjectStore(STORE);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => resolve(null);
      } catch (e) { resolve(null); }
    });
  }
  return dbPromise;
}

async function idb(mode, fn) {
  const base = await db();
  if (!base) return null;
  return new Promise((resolve) => {
    try {
      const tx = base.transaction(STORE, mode);
      const req = fn(tx.objectStore(STORE));
      tx.oncomplete = () => resolve(req?.result ?? null);
      tx.onerror = () => resolve(null);
    } catch (e) { resolve(null); }
  });
}

// Les données d'un compte ne sont jamais montrées à un autre compte.
function owner() {
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (/^sb-.*-auth-token$/.test(k)) {
        const s = JSON.parse(localStorage.getItem(k));
        if (s?.user?.id) return s.user.id;
      }
    }
  } catch (e) {}
  return 'invite';
}

export function clearOfflineData() {
  return idb('readwrite', store => store.clear());
}

// Bandeau discret en haut de l'écran, avec l'heure des données affichées.
let oldestShown = null;
function showBanner(savedAt) {
  oldestShown = oldestShown ? Math.min(oldestShown, savedAt) : savedAt;
  const d = new Date(oldestShown);
  const when = `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')} à ${d.getHours()}h${d.getMinutes() ? String(d.getMinutes()).padStart(2, '0') : ''}`;
  const text = `Hors connexion : infos du ${when}`;
  const render = () => {
    let bar = document.getElementById('bligo-offline-bar');
    if (!bar) {
      bar = document.createElement('div');
      bar.id = 'bligo-offline-bar';
      bar.setAttribute('role', 'status');
      bar.style.cssText = 'position:fixed;left:50%;transform:translateX(-50%);bottom:calc(env(safe-area-inset-bottom, 0px) + 86px);z-index:9999;'
        + 'background:#083133;color:#fff;font:600 12px/1.2 Inter,system-ui,sans-serif;padding:7px 12px;border-radius:999px;'
        + 'box-shadow:0 4px 14px rgba(0,0,0,.18);white-space:nowrap;pointer-events:none;';
      document.body.appendChild(bar);
    }
    bar.textContent = text;
  };
  if (document.body) render(); else document.addEventListener('DOMContentLoaded', render, { once: true });
}

function hideBanner() {
  oldestShown = null;
  document.getElementById('bligo-offline-bar')?.remove();
}
window.addEventListener('online', () => setTimeout(() => { if (navigator.onLine) hideBanner(); }, 1500));

function offlineResponse() {
  return new Response(JSON.stringify({ message: OFFLINE_MESSAGE, code: 'OFFLINE', details: null, hint: null }), {
    status: 503, headers: { 'Content-Type': 'application/json' },
  });
}

function fromSaved(saved) {
  showBanner(saved.t);
  return new Response(saved.body, { status: saved.status, headers: saved.headers });
}

async function save(key, res) {
  try {
    const headers = {};
    ['content-type', 'content-range', 'preference-applied'].forEach(h => { const v = res.headers.get(h); if (v) headers[h] = v; });
    const body = await res.text();
    await idb('readwrite', store => store.put({ t: Date.now(), status: res.status, headers, body }, key));
  } catch (e) {}
}

// fetch donné à Supabase : seules les requêtes vers l'API de données passent ici.
export function offlineFetch(supabaseUrl) {
  const restBase = supabaseUrl.replace(/\/$/, '') + '/rest/v1/';
  return async function (input, init = {}) {
    const url = typeof input === 'string' ? input : input.url;
    const method = (init.method || (typeof input === 'string' ? 'GET' : input.method) || 'GET').toUpperCase();
    if (!url.startsWith(restBase)) return fetch(input, init);

    const isRead = method === 'GET' || method === 'HEAD' || (method === 'POST' && READ_RPC.test(url));
    if (!isRead) {
      if (navigator.onLine === false) return offlineResponse();
      try { return await fetch(input, init); } catch (e) { return offlineResponse(); }
    }

    const key = `${owner()}|${method} ${url}|${typeof init.body === 'string' ? init.body : ''}`;
    const savedPromise = idb('readonly', store => store.get(key))
      .then(s => (s && Date.now() - s.t < MAX_AGE ? s : null));

    if (navigator.onLine === false) {
      const saved = await savedPromise;
      return saved ? fromSaved(saved) : offlineResponse();
    }

    const network = fetch(input, init).then(async (res) => {
      if (res.ok) { await save(key, res.clone()); hideBanner(); }
      return res;
    });
    network.catch(() => {});
    // Réseau faible : après quelques secondes, on montre les données gardées
    // (la réponse du serveur, si elle finit par arriver, met tout de même le
    // téléphone à jour pour la prochaine fois).
    const slow = new Promise(resolve => setTimeout(() => resolve('lent'), SLOW_MS));
    try {
      const first = await Promise.race([network, slow]);
      if (first !== 'lent') return first;
      const saved = await savedPromise;
      return saved ? fromSaved(saved) : await network;
    } catch (e) {
      const saved = await savedPromise;
      return saved ? fromSaved(saved) : offlineResponse();
    }
  };
}

// Sans réseau, la session expirée ne peut pas être renouvelée : on garde
// celle du téléphone pour que l'usager reste connecté (ses données sont là),
// elle sera renouvelée au retour du réseau.
export function keepSessionOffline(supabase) {
  const original = supabase.auth.getSession.bind(supabase.auth);
  supabase.auth.getSession = async function () {
    const result = await original();
    if (result?.data?.session || !result?.error) return result;
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (/^sb-.*-auth-token$/.test(k)) {
          const s = JSON.parse(localStorage.getItem(k));
          if (s?.user?.id) return { data: { session: s }, error: null };
        }
      }
    } catch (e) {}
    return result;
  };
}

// Couvertures non chargées sans réseau : on masque l'image cassée, la carte
// garde son fond coloré.
document.addEventListener('error', (e) => {
  const el = e.target;
  if (el?.tagName === 'IMG' && navigator.onLine === false) el.style.visibility = 'hidden';
}, true);
