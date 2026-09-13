import { supabase } from './supabaseClient.js';

// Pastille "Réservation" de la barre du bas : nombre de livres actuellement
// réservés ou empruntés (en préparation, prêts, ou empruntés et pas encore
// à échéance) — pour rappel visuel du quota (3 livres adultes + 3 jeunesse,
// renouvelable tous les 3 semaines une fois rendus).
export async function updateReservationBadge(userId) {
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
