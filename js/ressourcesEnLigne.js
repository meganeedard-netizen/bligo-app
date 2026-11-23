// Ressources numériques (23/11/2026) : accueil et profil de l'appli usager.
import { showDialog, showSnackbar } from './ui.js?v=20261023';
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const DIGITAL_ICONS = { livres: '📚', presse: '📰', autoformation: '🎓', musique: '🎵', cinema: '🎬', jeunesse: '🧸', autre: '🌐' };

export async function loadDigital(supabase, communeId) {
  const { data, error } = await supabase.from('digital_resources').select('*').eq('commune_id', communeId).order('sort_order').order('id');
  if (error) return [];
  const today = new Date().toLocaleDateString('sv-SE');
  return (data || []).filter(r => r.active !== false && (!r.expires_on || r.expires_on >= today) && /^https?:\/\//i.test(r.url));
}

// member : true (adhérent à jour), false (connecté, pas à jour), null (sans compte).
export function bindDigital(root, supabase, resources, member) {
  root.querySelectorAll('[data-digital]').forEach(a => a.addEventListener('click', ev => {
    const r = resources.find(x => String(x.id) === a.dataset.digital);
    if (!r) return;
    if (r.members_only && member !== true) {
      ev.preventDefault();
      showDialog({ title: r.name, message: member === null
        ? 'Cette ressource est réservée aux adhérents. Connecte-toi ou crée ton compte pour en profiter.'
        : 'Cette ressource est réservée aux adhérents à jour. Passe à l\'accueil de ta médiathèque pour activer ton adhésion.' });
      return;
    }
    // Connexion automatique : le lien du fournisseur est ouvert avec un ticket CAS
    // (l'appli mobile n'a pas de session dans le navigateur externe).
    if (r.cas_service_prefix && member === true && r.url.startsWith(r.cas_service_prefix)) {
      ev.preventDefault();
      const tab = window.Capacitor?.isNativePlatform?.() ? null : window.open('', '_blank');
      supabase.rpc('cas_issue_ticket', { p_service: r.url }).then(({ data, error }) => {
        const target = error || !data ? r.url : data;
        if (tab) { tab.opener = null; tab.location = target; }
        else if (window.Capacitor?.isNativePlatform?.()) window.open(target, '_blank');
        else showSnackbar('Autorise les fenêtres pour ouvrir cette ressource.');
      });
    }
    if (member !== null) supabase.rpc('count_digital_open', { p_resource_id: r.id }).then(() => {}, () => {});
  }));
}

export function digitalCards(resources) {
  return resources.map(r => `
    <a href="${esc(r.url)}" target="_blank" rel="noopener" data-digital="${r.id}" class="shrink-0 w-36 rounded-2xl bg-white shadow-sm p-3 flex flex-col gap-1.5">
      <span class="text-2xl leading-none">${DIGITAL_ICONS[r.kind] || '🌐'}</span>
      <span class="text-sm font-bold text-ink leading-snug line-clamp-2">${esc(r.name)}</span>
      ${r.description ? `<span class="text-[11px] text-ink/55 leading-snug line-clamp-2">${esc(r.description)}</span>` : ''}
    </a>`).join('');
}

export function digitalRows(resources) {
  return resources.map(r => `
    <a href="${esc(r.url)}" target="_blank" rel="noopener" data-digital="${r.id}" class="profile-row">
      <span class="min-w-0 flex items-center gap-3">
        <span class="text-xl shrink-0">${DIGITAL_ICONS[r.kind] || '🌐'}</span>
        <span class="min-w-0"><span class="block truncate">${esc(r.name)}</span>
        ${r.description ? `<span class="block text-xs text-ink/50 font-normal">${esc(r.description)}</span>` : ''}</span>
      </span><span class="profile-chevron">›</span></a>`).join('');
}
