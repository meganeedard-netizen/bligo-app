// BliGO - badges de lecteur (29/10/2026).
// Liste des badges, fenêtre d'un badge et partage (story ou à un ami),
// communs à la page Points et à l'accueil. L'accueil ouvre la fenêtre tout
// seul quand un badge vient d'être débloqué (points validés au comptoir).

export const BADGES = [
  { id: 'badge_01', name: 'Premier Chapitre', type: 'niveau', level: 1, threshold: 30, img: 'img/badges/badge-1.png', message: "📖 Félicitations ! Tu viens de débloquer le badge Premier Chapitre. Ton aventure BliGO commence aujourd'hui !" },
  { id: 'badge_02', name: 'Petit Curieux', type: 'niveau', level: 2, threshold: 100, img: 'img/badges/badge-2.png', message: "🔍 Bravo ! Badge Petit Curieux débloqué. Ta passion pour la lecture commence à porter ses fruits dans le quartier !" },
  { id: 'badge_03', name: 'Dénicheur', type: 'niveau', level: 3, threshold: 250, img: 'img/badges/badge-3.png', message: "🎯 Bien joué ! Tu as débloqué le badge Dénicheur. Trouver les plus belles pépites de la commune, c'est ta spécialité !" },
  { id: 'badge_04', name: 'Bouquineur', type: 'niveau', level: 4, threshold: 500, img: 'img/badges/badge-4.png', message: "📚 Super ! Badge Bouquineur débloqué. Déjà 10 livres remis en circulation grâce à toi. Merci pour la communauté !" },
  { id: 'badge_05', name: 'Passeur de Mots', type: 'niveau', level: 5, threshold: 1000, img: 'img/badges/badge-5.png', message: "🤝 Impressionnant ! Tu obtiens le badge Passeur de Mots. Ta générosité fait voyager la culture de voisin en voisin !" },
  { id: 'badge_06', name: 'Dévoreur', type: 'niveau', level: 6, threshold: 2000, img: 'img/badges/badge-6.png', message: "🚀 Quel rythme ! Félicitations, tu as débloqué le badge Dévoreur. Plus rien n'arrête ta soif de lecture !" },
  { id: 'badge_07', name: 'Bibliophile', type: 'niveau', level: 7, threshold: 3500, img: 'img/badges/badge-7.png', message: "🌟 Chapeau bas ! Le badge Bibliophile est à toi. Un véritable pilier de la lecture partagée au cœur de ta commune !" },
  { id: 'badge_08', name: 'Gardien du Savoir', type: 'niveau', level: 8, threshold: 5000, img: 'img/badges/badge-8.png', message: "🏰 Incroyable ! Tu décroches le badge Gardien du Savoir. 100 livres partagés, un immense merci pour ce formidable impact local !" },
  { id: 'badge_09', name: 'Maître des Pages', type: 'niveau', level: 9, threshold: 7500, img: 'img/badges/badge-9.png', message: "👑 Légendaire ! Badge Maître des Pages débloqué. Ton engagement inspire toute la communauté BliGO !" },
  { id: 'badge_10', name: 'Légende BliGO', type: 'niveau', level: 10, threshold: 10000, img: 'img/badges/badge-10.png', message: "🏆 Sommet atteint ! Bravo, tu es officiellement une Légende BliGO. La culture de ta commune te dit un grand MERCI !" },
  { id: 'badge_sp_01', name: 'Plume Locale', type: 'special', conditionText: '150 points BliGO sur la catégorie « Plume Locale »', img: 'img/badges/badge-special-1.png', message: "🌴 Bravo péyi ! Tu as débloqué le badge Plume Locale. Merci de faire rayonner les auteurs et la culture du territoire !" },
  { id: 'badge_sp_02', name: 'Cœur Généreux', type: 'special', conditionText: '5 dons de livres validés au total', img: 'img/badges/badge-special-2.png', message: "💛 Un grand Cœur ! Tu as débloqué le badge Cœur Généreux. Grâce à tes dons, tu donnes une seconde vie aux livres !" },
];

// Badges d'un profil, avec unlocked selon le niveau et les badges spéciaux.
export function badgesFor(profile) {
  const tier = profile?.badge_tier || 0;
  return BADGES.map(b => ({
    ...b,
    unlocked: b.type === 'niveau'
      ? tier >= b.level
      : (b.id === 'badge_sp_01' ? !!profile?.plume_locale_unlocked : !!profile?.coeur_genereux_unlocked),
  }));
}

// Badges débloqués depuis la dernière visite, retenus sur le téléphone. La
// toute première fois, les badges déjà acquis sont notés sans fenêtre : on ne
// fête que ce qui arrive ensuite.
export function takeNewBadges(userId, profile) {
  if (!userId || !profile) return [];
  const key = 'bligo_badges_vus_' + userId;
  const unlocked = badgesFor(profile).filter(b => b.unlocked);
  let seen = null;
  try { seen = JSON.parse(localStorage.getItem(key) || 'null'); } catch (e) { seen = null; }
  try { localStorage.setItem(key, JSON.stringify(unlocked.map(b => b.id))); } catch (e) { /* stockage indisponible */ }
  if (!Array.isArray(seen)) return [];
  return unlocked.filter(b => !seen.includes(b.id));
}

const MODAL_HTML = `
<div id="badge-modal-backdrop" class="hidden fixed inset-0 z-50 bg-black/50 items-center justify-center p-5">
  <div class="bg-white rounded-2xl w-full max-w-sm relative overflow-hidden max-h-[90vh] overflow-y-auto">
    <button type="button" data-badge-close style="touch-action: manipulation;" class="absolute top-3 left-3 w-8 h-8 rounded-full bg-white/90 shadow flex items-center justify-center text-ink/60 hover:text-ink z-10" aria-label="Fermer">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6L6 18M6 6l12 12"/></svg>
    </button>
    <div class="pt-10 pb-6 px-6 text-center bg-gradient-to-br from-mango-50 to-hibiscus-50">
      <p id="badge-modal-new" class="hidden text-sm font-extrabold text-mango-700 mb-2">🎉 Nouveau badge débloqué !</p>
      <img id="badge-modal-img" src="" alt="" class="w-32 h-32 mx-auto mb-3">
      <p id="badge-modal-type" class="text-[11px] font-bold uppercase tracking-wide text-hibiscus-600 mb-1"></p>
      <p id="badge-modal-name" class="text-lg font-extrabold text-ink"></p>
    </div>
    <div class="p-6">
      <p id="badge-modal-message" class="text-sm text-ink/75 leading-relaxed text-center mb-5"></p>
      <div id="badge-modal-share" class="hidden space-y-2">
        <button id="badge-modal-story-btn" type="button" style="touch-action: manipulation;" class="w-full bg-brand text-white rounded-2xl py-3 text-base font-semibold active:scale-[0.98] transition">Partager en story</button>
        <p class="text-[11px] text-center text-ink/50">Instagram, TikTok, Snapchat…</p>
        <button id="badge-modal-share-btn" type="button" style="touch-action: manipulation;" class="w-full bg-[#EEEDF2] text-ink rounded-2xl py-3 text-base font-semibold active:scale-[0.98] transition">Envoyer à un ami</button>
      </div>
      <p id="badge-modal-share-msg" class="text-xs text-center text-ink/50 mt-2"></p>
    </div>
  </div>
</div>`;

function ensureModal() {
  let backdrop = document.getElementById('badge-modal-backdrop');
  if (backdrop) return backdrop;
  document.body.insertAdjacentHTML('beforeend', MODAL_HTML);
  backdrop = document.getElementById('badge-modal-backdrop');
  backdrop.addEventListener('click', e => {
    if (e.target === backdrop || e.target.closest('[data-badge-close]')) closeBadgeModal();
  });
  return backdrop;
}

export function openBadgeModal(b, { nouveau = false } = {}) {
  const backdrop = ensureModal();
  document.getElementById('badge-modal-new').classList.toggle('hidden', !nouveau);
  document.getElementById('badge-modal-img').src = b.img;
  document.getElementById('badge-modal-img').className = `w-32 h-32 mx-auto mb-3 ${b.unlocked ? '' : 'grayscale opacity-40'}`;
  document.getElementById('badge-modal-type').textContent = b.type === 'niveau' ? `Niveau ${b.level}` : 'Badge spécial';
  document.getElementById('badge-modal-name').textContent = b.name;

  const shareBlock = document.getElementById('badge-modal-share');
  document.getElementById('badge-modal-share-msg').textContent = '';

  if (b.unlocked) {
    document.getElementById('badge-modal-message').textContent = b.message;
    shareBlock.classList.remove('hidden');
    document.getElementById('badge-modal-share-btn').onclick = () => shareBadge(b);
    document.getElementById('badge-modal-story-btn').onclick = () => shareBadgeStory(b);
  } else {
    document.getElementById('badge-modal-message').textContent = `Débloque ce badge : ${b.conditionText || (b.threshold + ' points BliGO')}.`;
    shareBlock.classList.add('hidden');
  }

  backdrop.classList.remove('hidden');
  backdrop.classList.add('flex');
}

export function closeBadgeModal() {
  const backdrop = document.getElementById('badge-modal-backdrop');
  if (!backdrop) return;
  backdrop.classList.add('hidden');
  backdrop.classList.remove('flex');
}

async function shareBadge(b) {
  const shareText = `J'ai débloqué le badge « ${b.name} » sur BliGO ! ${b.message}`;
  const msg = document.getElementById('badge-modal-share-msg');
  msg.textContent = '';

  // On essaie d'abord de partager l'image du badge elle-même (pas juste le
  // texte) - nécessite de la récupérer en fichier avant de la proposer au
  // partage natif du téléphone.
  let file = null;
  try {
    const response = await fetch(b.img);
    const blob = await response.blob();
    file = new File([blob], `badge-${b.id}.png`, { type: blob.type || 'image/png' });
  } catch (e) {
    file = null;
  }

  const canShareFile = file && navigator.canShare && navigator.canShare({ files: [file] });

  if (canShareFile || navigator.share) {
    try {
      await navigator.share(canShareFile
        ? { files: [file], title: 'BliGO', text: shareText }
        : { title: 'BliGO', text: shareText });
    } catch (e) {
      // Partage annulé par l'usager - rien à faire.
    }
    return;
  }

  try {
    await navigator.clipboard.writeText(shareText);
    msg.textContent = 'Texte copié ! Colle-le où tu veux.';
  } catch (e) {
    msg.textContent = shareText;
  }
}

// Partage en story (28/10/2026) : une image seule au format story
// (1080 x 1920), sans texte joint. Avec un texte, l'iPhone ne propose pas
// Instagram, TikTok ni Snapchat dans la feuille de partage.
function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}

function wrapLines(ctx, text, maxWidth) {
  const lines = [];
  let line = '';
  for (const word of text.split(' ')) {
    const next = line ? `${line} ${word}` : word;
    if (line && ctx.measureText(next).width > maxWidth) { lines.push(line); line = word; }
    else line = next;
  }
  if (line) lines.push(line);
  return lines;
}

async function buildBadgeStory(b) {
  const W = 1080, H = 1920;
  const canvas = document.createElement('canvas');
  canvas.width = W; canvas.height = H;
  const ctx = canvas.getContext('2d');
  try { await document.fonts.load('800 80px Inter'); await document.fonts.load('600 40px Inter'); } catch (e) {}

  const bg = ctx.createLinearGradient(0, 0, 0, H);
  bg.addColorStop(0, '#1B4B43');
  bg.addColorStop(1, '#0E2A25');
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, W, H);
  const glow = ctx.createRadialGradient(W / 2, 860, 40, W / 2, 860, 560);
  glow.addColorStop(0, 'rgba(255, 155, 46, 0.45)');
  glow.addColorStop(1, 'rgba(255, 155, 46, 0)');
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, W, H);

  const [logo, badge] = await Promise.all([loadImage('img/bligo-logo-sombre.png'), loadImage(b.img)]);
  const logoW = 300;
  ctx.drawImage(logo, (W - logoW) / 2, 170, logoW, logoW * logo.height / logo.width);

  ctx.fillStyle = 'rgba(255, 255, 255, 0.10)';
  ctx.beginPath(); ctx.arc(W / 2, 860, 330, 0, Math.PI * 2); ctx.fill();
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(badge, W / 2 - 260, 860 - 260, 520, 520);

  ctx.textAlign = 'center';
  ctx.fillStyle = '#FFB86B';
  ctx.font = '600 44px Inter, sans-serif';
  ctx.fillText(b.type === 'niveau' ? `Badge niveau ${b.level} débloqué` : 'Badge spécial débloqué', W / 2, 1320);
  ctx.fillStyle = '#FFFFFF';
  ctx.font = '800 92px Inter, sans-serif';
  wrapLines(ctx, b.name, W - 160).forEach((l, i) => ctx.fillText(l, W / 2, 1440 + i * 104));
  ctx.fillStyle = 'rgba(255, 255, 255, 0.75)';
  ctx.font = '500 34px Inter, sans-serif';
  ctx.fillText("Avec BliGO, l'appli de ma Médiathèque Municipale", W / 2, 1760);

  const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
  return new File([blob], `bligo-${b.id}-story.png`, { type: 'image/png' });
}

async function shareBadgeStory(b) {
  const msg = document.getElementById('badge-modal-share-msg');
  msg.textContent = '';
  let file = null;
  try { file = await buildBadgeStory(b); } catch (e) { file = null; }
  if (file && navigator.canShare && navigator.canShare({ files: [file] })) {
    try { await navigator.share({ files: [file] }); } catch (e) { /* partage annulé */ }
    return;
  }
  if (file) {
    // Navigateur sans partage de fichier (ordinateur) : téléchargement.
    const a = document.createElement('a');
    a.href = URL.createObjectURL(file);
    a.download = file.name;
    a.click();
    msg.textContent = 'Image enregistrée : ajoute-la à ta story depuis ton appli.';
    return;
  }
  msg.textContent = "L'image n'a pas pu être créée, réessaie dans un instant.";
}
