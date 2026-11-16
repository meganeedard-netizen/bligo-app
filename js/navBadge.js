import { supabase } from './supabaseClient.js?v=20261103b';
import { updateProfileBadge } from './verifEmail.js?v=20261103b';

// Pastille "Réservation" de la barre du bas : nombre de livres actuellement
// réservés ou empruntés (en préparation, prêts, ou empruntés et pas encore
// à échéance) - pour rappel visuel du quota (3 livres adultes + 3 jeunesse,
// renouvelable tous les 3 semaines une fois rendus).
export async function updateReservationBadge(userId) {
  // Et la pastille « 1 » du Profil : adresse e-mail à vérifier (01/11/2026).
  updateProfileBadge(userId);
  updateAgendaBadge(userId);
  const badge = document.getElementById('nav-resa-badge');
  if (!badge) return;

  const { data, error } = await supabase
    .from('reservations')
    .select('status, return_due_at')
    .eq('user_id', userId)
    .in('status', ['preparation', 'pret', 'recupere']);

  if (error) { console.error(error); return; }

  const now = Date.now();
  const activeCount = (data || []).filter(r =>
    r.status === 'preparation' ||
    r.status === 'pret' ||
    (r.status === 'recupere' && r.return_due_at && new Date(r.return_due_at).getTime() > now)
  ).length;

  if (activeCount > 0) {
    badge.textContent = activeCount;
    badge.classList.remove('hidden');
  } else {
    badge.classList.add('hidden');
  }
}

// Alerte agenda (16/11/2026, demande du Sud Corse) : pastille sur l'onglet
// Agenda = nombre d'événements à venir ajoutés par la Médiathèque Municipale
// depuis la dernière visite de l'agenda (date gardée sur le téléphone).
// Première fois : on mémorise maintenant, sans pastille (pas d'alerte pour
// tout l'agenda déjà en place).
const AGENDA_KEY = uid => 'bligo_agenda_vu_' + uid;

export function agendaLastSeen(userId) {
  try { return localStorage.getItem(AGENDA_KEY(userId)); } catch { return null; }
}

export function markAgendaSeen(userId) {
  try { localStorage.setItem(AGENDA_KEY(userId), new Date().toISOString()); } catch {}
}

export async function updateAgendaBadge(userId) {
  const link = document.querySelector('nav a[href="agenda.html"]');
  if (!link || location.pathname.endsWith('agenda.html')) return;
  const seen = agendaLastSeen(userId);
  if (!seen) { markAgendaSeen(userId); return; }

  const { data: profile } = await supabase.from('profiles').select('commune_id').eq('id', userId).single();
  if (!profile?.commune_id) return;
  const { count, error } = await supabase
    .from('events')
    .select('id', { count: 'exact', head: true })
    .eq('commune_id', profile.commune_id)
    .gt('created_at', seen)
    .gte('event_date', new Date().toISOString());
  if (error || !count) return;

  let badge = document.getElementById('nav-agenda-badge');
  if (!badge) {
    const svg = link.querySelector('svg');
    if (!svg) return;
    const wrap = document.createElement('span');
    wrap.className = 'relative';
    svg.replaceWith(wrap);
    wrap.appendChild(svg);
    badge = document.createElement('span');
    badge.id = 'nav-agenda-badge';
    badge.className = 'absolute -top-1 -right-1.5 min-w-[15px] h-[15px] px-1 rounded-full bg-hibiscus-600 text-white text-[9px] font-bold flex items-center justify-center leading-none';
    badge.setAttribute('aria-label', count + ' nouvel' + (count > 1 ? 's' : '') + ' événement' + (count > 1 ? 's' : ''));
    wrap.appendChild(badge);
  }
  badge.textContent = count > 9 ? '9+' : String(count);
}
