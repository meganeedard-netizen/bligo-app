// Snackbar et pop-up centré aux couleurs de l'appli (16/10/2026) : remplacent
// alert() et confirm(), jugés pas jolis aux tests de Mégane.

const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

let snackbarTimer = null;

// Bandeau en bas de l'écran, au-dessus de la barre de navigation.
export function showSnackbar(message, { duration = 3500 } = {}) {
  let el = document.getElementById('bligo-snackbar');
  if (!el) {
    el = document.createElement('div');
    el.id = 'bligo-snackbar';
    el.setAttribute('role', 'status');
    el.className = 'fixed left-1/2 z-[70] w-[calc(100%-2rem)] max-w-sm -translate-x-1/2 rounded-2xl bg-ink text-white text-sm font-medium leading-snug px-4 py-3.5 shadow-xl transition-all duration-300 opacity-0 translate-y-3 pointer-events-none';
    el.style.bottom = 'calc(5.5rem + env(safe-area-inset-bottom))';
    el.style.backgroundColor = '#1B4B43';
    document.body.appendChild(el);
  }
  el.textContent = message;
  requestAnimationFrame(() => {
    el.classList.remove('opacity-0', 'translate-y-3');
  });
  clearTimeout(snackbarTimer);
  snackbarTimer = setTimeout(() => el.classList.add('opacity-0', 'translate-y-3'), duration);
}

// Pop-up centré. buttons : [{ label, value, primary, danger }] ; renvoie la valeur du
// bouton choisi (null si fermé en touchant le fond).
export function showDialog({ title = '', message = '', buttons = [{ label: 'Compris', value: true, primary: true }] } = {}) {
  return new Promise(resolve => {
    const backdrop = document.createElement('div');
    backdrop.className = 'fixed inset-0 z-[65] bg-black/40 backdrop-blur-sm flex items-center justify-center p-6';
    backdrop.innerHTML = `
      <div class="bg-white rounded-3xl shadow-2xl max-w-sm w-full p-6 text-center">
        ${title ? `<p class="text-lg font-bold text-ink mb-2">${esc(title)}</p>` : ''}
        ${message ? `<p class="text-sm text-ink/65 leading-relaxed">${esc(message)}</p>` : ''}
        <div class="flex flex-col gap-2 mt-6">
          ${buttons.map((b, i) => `<button data-i="${i}" class="w-full rounded-2xl py-3 text-base font-semibold active:scale-[0.98] transition ${b.danger ? 'bg-red-600 text-white' : b.primary ? 'bg-brand text-white' : 'bg-[#EEEDF2] text-ink/70'}">${esc(b.label)}</button>`).join('')}
        </div>
      </div>`;
    const close = value => { backdrop.remove(); resolve(value); };
    backdrop.querySelectorAll('button[data-i]').forEach(btn => {
      btn.onclick = () => close(buttons[Number(btn.dataset.i)].value);
    });
    backdrop.onclick = e => { if (e.target === backdrop) close(null); };
    document.body.appendChild(backdrop);
  });
}

// Oui / non : renvoie true seulement si l'usager confirme.
export async function confirmDialog({ title, message, confirmLabel, cancelLabel }) {
  const value = await showDialog({
    title, message,
    buttons: [{ label: confirmLabel, value: true, primary: true }, { label: cancelLabel, value: false }],
  });
  return value === true;
}

// Messages d'erreur en français (23/10/2026) : Supabase, la base et le
// navigateur répondent souvent en anglais (« Invalid login credentials »,
// « Load failed », « duplicate key »…). Un message déjà en français est gardé.
export function frError(error) {
  const m = String(error?.message || error || '');
  if (!m) return 'Une erreur est survenue. Réessaie dans un instant.';
  if (/banned/i.test(m)) return "Ton accès à l'appli est fermé. Demande à ta médiathèque de le rouvrir.";
  if (/invalid login credentials/i.test(m)) return 'E-mail ou mot de passe incorrect.';
  if (/load failed|failed to fetch|networkerror|network request failed|fetch failed/i.test(m)) return 'Connexion au serveur impossible. Vérifie ta connexion internet et réessaie.';
  if (/already registered|already been registered|user already exists/i.test(m)) return 'Un compte existe déjà avec cet e-mail.';
  if (/password should be at least|weak password|password is too short/i.test(m)) return 'Le mot de passe doit contenir au moins 6 caractères.';
  if (/same password|different from the old/i.test(m)) return "Le nouveau mot de passe doit être différent de l'ancien.";
  if (/invalid email|unable to validate email|email address .* is invalid/i.test(m)) return "L'adresse e-mail n'est pas valide.";
  if (/rate limit|too many requests|security purposes|after \d+ seconds/i.test(m)) return 'Trop de tentatives. Patiente une minute puis réessaie.';
  if (/token has expired|otp.*(expired|invalid)|expired or is invalid/i.test(m)) return 'Code incorrect ou expiré. Vérifie-le ou demande un nouveau code.';
  if (/jwt expired|session.*(missing|expired|not found)|refresh token/i.test(m)) return 'Ta session a expiré. Reconnecte-toi.';
  if (/duplicate key|already exists|unique constraint/i.test(m)) return 'Cet élément existe déjà.';
  if (/violates foreign key/i.test(m)) return 'Impossible : cet élément est encore utilisé ailleurs.';
  if (/violates check constraint|invalid input (syntax|value)|out of range/i.test(m)) return "Une valeur saisie n'est pas valide. Vérifie les champs.";
  if (/violates not-null/i.test(m)) return 'Un champ obligatoire est vide.';
  if (/row-level security|permission denied|not authorized|unauthorized|forbidden/i.test(m)) return "Action non autorisée pour ce compte.";
  if (/payload too large|file size|exceeded the maximum/i.test(m)) return 'Le fichier est trop lourd.';
  if (/timeout|timed out/i.test(m)) return 'Le serveur met trop de temps à répondre. Réessaie dans un instant.';
  if (/[àâäçéèêëîïôöùûüÿœ]/i.test(m)) return m;
  if (/\b(the|is|not|of|to|for|with|failed|error|invalid|could|does|exist|cannot|unable|unexpected|column|relation|function)\b/i.test(m)) return 'Une erreur est survenue. Réessaie dans un instant.';
  return m;
}
