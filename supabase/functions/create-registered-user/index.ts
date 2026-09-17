// BliGO — Créer un compte inscrit depuis le logiciel agent, sans passer par
// l'application (17/09/2026)
//
// Pour une personne qui n'a pas l'application (pas de smartphone, ne veut
// pas l'installer...) : l'agent saisit ses informations sur place, le compte
// est créé ET confirmé immédiatement (identité déjà vérifiée en personne,
// contrairement à une préinscription en ligne qui attend encore un passage).
//
// Créer un utilisateur Supabase exige la clé service_role, jamais exposée
// côté navigateur — cette fonction la détient côté serveur. Contrairement à
// create-agent-account (réservée à la direction), n'importe quel agent peut
// appeler celle-ci : ajouter un inscrit est une tâche de guichet courante,
// pas une action sensible sur les comptes du personnel.
//
// Appelée depuis admin.html (écran Inscrits) via
// supabase.functions.invoke('create-registered-user', { body: {...} }).
//
// SUPABASE_URL, SUPABASE_ANON_KEY et SUPABASE_SERVICE_ROLE_KEY sont injectées
// automatiquement par Supabase pour toute Edge Function.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
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
    .select('role')
    .eq('id', caller.id)
    .single();

  const isAgent = !callerProfileError && callerProfile && ['agent', 'super_admin'].includes(callerProfile.role);
  if (!isAgent) return json({ ok: false, message: 'Réservé aux agents' }, 403);

  let body: { full_name?: string; email?: string; password?: string; tariff_category?: string; commune_id?: number };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, message: 'Corps de requête invalide' }, 400);
  }

  const { full_name, email, password, tariff_category, commune_id } = body;

  if (!full_name?.trim() || !email?.trim() || !password || password.length < 8) {
    return json({ ok: false, message: 'Nom, e-mail et mot de passe (8 caractères minimum) sont obligatoires.' }, 400);
  }
  if (!['mineur', 'majeur', 'gratuit'].includes(tariff_category ?? '')) {
    return json({ ok: false, message: 'Catégorie tarifaire invalide (mineur, majeur ou gratuit).' }, 400);
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
      account_type: 'officiel',
      commune_id: commune_id ?? null,
      commune_confirmed: true,
      registration_status: 'valide',
      tariff_category,
      validated_at: new Date().toISOString(),
      validated_by: caller.id,
    })
    .eq('id', created.user.id);

  if (profileError) {
    return json({ ok: false, message: 'Compte créé mais profil non configuré : ' + profileError.message }, 500);
  }

  return json({ ok: true, user_id: created.user.id });
});
