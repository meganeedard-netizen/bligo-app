import { supabase } from './supabaseClient.js?v=20261023';
import { showDialog, frError } from './ui.js?v=20261023';

// Vérification de l'adresse e-mail « plus tard » (01/11/2026, demandé par
// Mégane après les tests Android) : le compte s'ouvre sans attendre le code,
// l'usager vérifie son adresse quand il veut (Profil > Vérifier mon compte).
// Tant que ce n'est pas fait : pas de commande ni d'inscription à un
// événement (bloqué aussi côté base, sql/email_verifie_2026-11-01.sql).

let cache = null;

export async function isEmailVerified(userId, { refresh = false } = {}) {
  if (cache && cache.userId === userId && !refresh) return cache.verified;
  const { data } = await supabase.from('profiles').select('email_verifie').eq('id', userId).maybeSingle();
  // Profil illisible (réseau) : on ne bloque pas, la base refusera au besoin.
  const verified = data ? data.email_verifie !== false : true;
  cache = { userId, verified };
  return verified;
}

// Code à 6 chiffres envoyé par e-mail (modèle « Magic Link » de Supabase,
// réécrit en français avec {{ .Token }}).
// Supabase refuse un deuxième envoi à la même adresse dans la minute
// (« Trop de tentatives » affiché sans que l'usager ait rien essayé,
// 03/11/2026) : le code envoyé reste valable 1 h, on ne renvoie donc rien
// pendant cette minute, et un refus pour ce motif n'est pas une erreur.
const SENT_KEY = email => 'bligo_code_envoye_' + String(email).toLowerCase();

export function codeWaitSeconds(email) {
  let sent = 0;
  try { sent = Number(localStorage.getItem(SENT_KEY(email))) || 0; } catch (e) {}
  return Math.max(0, Math.ceil((sent + 60000 - Date.now()) / 1000));
}

export async function sendVerifyCode(email) {
  if (codeWaitSeconds(email) > 0) return null;
  const { error } = await supabase.auth.signInWithOtp({ email, options: { shouldCreateUser: false } });
  if (error && !/rate limit|too many requests|security purposes|after \d+ seconds/i.test(error.message || '')) return error;
  try { localStorage.setItem(SENT_KEY(email), String(Date.now())); } catch (e) {}
  return null;
}

export async function checkVerifyCode(email, token) {
  const { error } = await supabase.auth.verifyOtp({ email, token, type: 'email' });
  if (error) return error;
  const { error: rpcError } = await supabase.rpc('confirmer_mon_email');
  if (rpcError) return rpcError;
  if (cache) cache.verified = true;
  document.getElementById('nav-profil-badge')?.classList.add('hidden');
  return null;
}

// Supabase n'accepte qu'un envoi par minute environ : bouton grisé 60 s.
export function startCooldown(btnOrId, label, seconds = 60) {
  const btn = typeof btnOrId === 'string' ? document.getElementById(btnOrId) : btnOrId;
  let left = seconds;
  if (left <= 0) return;
  btn.disabled = true;
  btn.textContent = `${label} (${left} s)`;
  const timer = setInterval(() => {
    left -= 1;
    if (left <= 0) {
      clearInterval(timer);
      btn.disabled = false;
      btn.textContent = label;
      return;
    }
    btn.textContent = `${label} (${left} s)`;
  }, 1000);
}

const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// Fenêtre du code : envoie le code à l'ouverture. Renvoie true si l'adresse
// a été vérifiée, false si l'usager a choisi « Plus tard ».
export function openVerifyModal(email) {
  return new Promise(resolve => {
    const backdrop = document.createElement('div');
    backdrop.className = 'fixed inset-0 z-[66] bg-black/40 backdrop-blur-sm flex items-center justify-center p-4';
    backdrop.innerHTML = `
      <form class="bg-white rounded-3xl shadow-2xl max-w-sm w-full p-6 flex flex-col gap-3">
        <p class="text-lg font-bold text-ink text-center">Vérifie ton adresse e-mail</p>
        <p class="text-xs text-ink/60 text-center leading-relaxed">Un code à 6 chiffres vient d'être envoyé à <span class="font-semibold text-ink">${esc(email)}</span>.</p>
        <input required data-code inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6" placeholder="••••••" class="w-full bg-[#EEEDF2] rounded-2xl px-4 py-4 text-center text-2xl font-bold tracking-[0.5em] text-ink outline-none focus:ring-2 focus:ring-mango-300">
        <p data-msg class="text-xs text-center min-h-[16px]"></p>
        <button type="submit" class="w-full bg-brand text-white rounded-2xl py-3.5 text-base font-semibold active:scale-[0.98] transition">Valider</button>
        <button type="button" data-resend class="w-full text-xs font-semibold text-mango-700 disabled:text-ink/35">Renvoyer le code</button>
        <button type="button" data-later class="w-full text-sm font-semibold text-ink/50 py-1">Plus tard</button>
        <p class="text-[11px] text-ink/45 text-center">Pense à regarder dans tes courriers indésirables.</p>
      </form>`;
    const form = backdrop.querySelector('form');
    const input = backdrop.querySelector('[data-code]');
    const msg = backdrop.querySelector('[data-msg]');
    const resendBtn = backdrop.querySelector('[data-resend]');
    const setMsg = (text, color) => { msg.textContent = text; msg.className = `text-xs text-center min-h-[16px] ${color}`; };
    const close = value => { backdrop.remove(); resolve(value); };

    const send = async () => {
      setMsg('Envoi du code…', 'text-ink/50');
      const error = await sendVerifyCode(email);
      if (error) { setMsg(frError(error), 'text-red-600'); return; }
      setMsg('', '');
      startCooldown(resendBtn, 'Renvoyer le code', codeWaitSeconds(email));
    };

    input.addEventListener('input', () => { input.value = input.value.replace(/\D/g, '').slice(0, 6); });
    resendBtn.onclick = send;
    backdrop.querySelector('[data-later]').onclick = () => close(false);
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const token = input.value.trim();
      if (!/^\d{6}$/.test(token)) { setMsg('Le code contient 6 chiffres.', 'text-red-600'); return; }
      setMsg('Vérification…', 'text-ink/50');
      const error = await checkVerifyCode(email, token);
      if (error) { setMsg(frError(error), 'text-red-600'); return; }
      close(true);
    });

    document.body.appendChild(backdrop);
    send();
    input.focus();
  });
}

// Avant de commander ou de s'inscrire à un événement : true si l'adresse est
// vérifiée (ou vient de l'être), sinon on explique et on propose de le faire.
export async function ensureEmailVerified(user, action) {
  if (await isEmailVerified(user.id)) return true;
  const choice = await showDialog({
    title: 'Vérifie ton adresse e-mail',
    message: `Avant ${action}, confirme ton adresse e-mail avec le code qu'on va t'envoyer. Ça prend 1 minute.`,
    buttons: [{ label: 'Vérifier mon compte', value: true, primary: true }, { label: 'Plus tard', value: false }],
  });
  if (!choice) return false;
  return openVerifyModal(user.email);
}

// Pastille « 1 » sur l'onglet Profil de la barre du bas tant que l'adresse
// n'est pas vérifiée (même style que la pastille Réservation).
export async function updateProfileBadge(userId) {
  const link = document.querySelector('nav a[href="profil.html"], nav a[data-app-href="profil.html"]');
  if (!link) return;
  let badge = document.getElementById('nav-profil-badge');
  if (!badge) {
    const svg = link.querySelector('svg');
    if (!svg) return;
    const wrap = document.createElement('span');
    wrap.className = 'relative';
    svg.replaceWith(wrap);
    wrap.appendChild(svg);
    badge = document.createElement('span');
    badge.id = 'nav-profil-badge';
    badge.className = 'hidden absolute -top-1 -right-1.5 min-w-[15px] h-[15px] px-1 rounded-full bg-mango-600 text-white text-[9px] font-bold flex items-center justify-center leading-none';
    badge.textContent = '1';
    wrap.appendChild(badge);
  }
  badge.classList.toggle('hidden', await isEmailVerified(userId));
}
