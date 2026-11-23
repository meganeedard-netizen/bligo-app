// BliGO - serveur CAS pour les ressources numériques (23/11/2026)
// Adresse à donner au fournisseur : https://<projet>.supabase.co/functions/v1/cas
//   /login?service=…           -> page de connexion BliGO
//   /serviceValidate?service=…&ticket=…  (CAS 2.0, aussi /p3/serviceValidate)
// Le ticket vaut une seule fois, 60 secondes, pour le service demandé. Le
// fournisseur reçoit un identifiant anonyme, propre à lui : ni nom ni e-mail.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const xml = (inner: string) => new Response(
  `<cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">${inner}</cas:serviceResponse>`,
  { headers: { 'Content-Type': 'application/xml; charset=utf-8', 'Cache-Control': 'no-store' } });
const fail = (code: string) => xml(`<cas:authenticationFailure code="${code}">${code}</cas:authenticationFailure>`);

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const action = url.pathname.split('/').filter(Boolean).pop();
  const service = url.searchParams.get('service') || '';
  if (action === 'login') {
    return Response.redirect('https://bligo.app/cas.html?service=' + encodeURIComponent(service), 302);
  }
  if (action === 'logout') return Response.redirect('https://bligo.app/accueil.html', 302);
  if (action === 'serviceValidate' || action === 'proxyValidate') {
    const ticket = url.searchParams.get('ticket') || '';
    if (!service || !ticket) return fail('INVALID_REQUEST');
    const { data, error } = await db.rpc('cas_consume_ticket', { p_ticket: ticket, p_service: service });
    if (error) { console.error(error.message); return fail('INTERNAL_ERROR'); }
    return data ? xml(`<cas:authenticationSuccess><cas:user>${data}</cas:user></cas:authenticationSuccess>`) : fail('INVALID_TICKET');
  }
  return new Response('Not found', { status: 404 });
});
