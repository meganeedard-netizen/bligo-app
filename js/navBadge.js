import { supabase } from './supabaseClient.js?v=20261016c';

// Onglet « Mon panier » de la barre du bas (16/10/2026) : la pastille compte
// les livres du panier, et l'onglet devient « Ma commande » quand le panier
// est vide mais qu'une commande est en cours (en préparation ou prête).
export async function updateReservationBadge(userId) {
  const badge = document.getElementById('nav-resa-badge');
  const label = document.getElementById('nav-resa-label');
  if (!badge) return;

  const { data, error } = await supabase
    .from('reservations')
    .select('status')
    .eq('user_id', userId)
    .in('status', ['panier', 'preparation', 'pret']);

  if (error) { console.error(error); return; }

  const cartCount = (data || []).filter(r => r.status === 'panier').length;
  const orderCount = (data || []).length - cartCount;
  const count = cartCount || orderCount;

  if (label) label.textContent = !cartCount && orderCount ? 'Ma commande' : 'Mon panier';
  if (count > 0) {
    badge.textContent = count;
    badge.classList.remove('hidden');
  } else {
    badge.classList.add('hidden');
  }
}
