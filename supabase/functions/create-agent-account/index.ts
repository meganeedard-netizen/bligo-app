// BliGO — Création d'un compte agent depuis le logiciel agent (16/09/2026, point 9)
//
// Créer un compte Supabase (auth.users) exige la clé service_role, qui ne doit
// jamais être exposée côté navigateur — sinon n'importe qui pourrait se créer
// un compte agent. Cette fonction la détient côté serveur, et vérifie elle-même
// que l'appelant est habilité (direction ou super_admin) avant de créer quoi
// que ce soit : ne jamais faire confiance à un contrôle fait uniquement côté
// client (admin.html cache déjà le bouton, mais ça n'est qu'un confort d'UI).
//
// Appelée depuis admin.html via supabase.functions.invoke('create-agent-account', ...),
// qui transmet automatiquement le jeton de l'agent connecté.
//
// SUPABASE_URL, SUPABASE_ANON_KEY et SUPABASE_SERVICE_ROLE_KEY sont injectées
// automatiquement par Supabase pour toute Edge Function.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ ok: false, message: 'Méthode non supportée' }, 405);

  const authHeader = req.headers.get('Authorization') ?? '';
  const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user: caller }, error: authError } = await callerClient.auth.getUser();
  if (authError || !caller) return json({ ok: false, message: 'Non authentifié' }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: callerProfile, error: callerProfileError } = await admin
    .from('profiles')
    .select('role, agent_level')
    .eq('id', caller.id)
    .single();

  const isDirection = !callerProfileError && callerProfile &&
    (callerProfile.role === 'super_admin' || (callerProfile.role === 'agent' && callerProfile.agent_level === 'direction'));

  if (!isDirection) return json({ ok: false, message: 'Réservé aux comptes direction' }, 403);

  let body: { full_name?: string; email?: string; password?: string; agent_level?: string; commune_id?: number };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, message: 'Corps de requête invalide' }, 400);
  }

  const { full_name, email, password, agent_level, commune_id } = body;

  if (!full_name?.trim() || !email?.trim() || !password || password.length < 8) {
    return json({ ok: false, message: 'Nom, e-mail et mot de passe (8 caractères minimum) sont obligatoires.' }, 400);
  }
  if (agent_level !== 'agent' && agent_level !== 'direction') {
    return json({ ok: false, message: 'Niveau invalide (agent ou direction).' }, 400);
  }

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email: email.trim(),
    password,
    email_confirm: true,
  });

  if (createError || !created?.user) {
    return json({ ok: false, message: createError?.message || 'Échec de la création du compte.' }, 400);
  }

  const { error: profileError } = await admin
    .from('profiles')
    .update({
      full_name: full_name.trim(),
      role: 'agent',
      agent_level,
      commune_id: commune_id ?? null,
      commune_confirmed: true,
    })
    .eq('id', created.user.id);

  if (profileError) {
    // Le compte auth existe déjà : on le signale plutôt que de le laisser à moitié configuré en silence.
    return json({ ok: false, message: 'Compte créé mais profil non configuré : ' + profileError.message }, 500);
  }

  return json({ ok: true, user_id: created.user.id });
});
