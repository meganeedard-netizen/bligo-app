// BliGO — Ajouter un enfant à une carte famille, sans e-mail (09/10/2026)
//
// Décision de Mégane le 09/10/2026 : les enfants n'ont pas de compte à eux,
// le parent gère pour eux (voir sql/add_family_and_digital.sql). Chaque
// enfant a quand même sa propre fiche et son numéro d'abonné (on sait qui
// emprunte quoi, restrictions mineurs appliquées) : il faut donc un vrai
// utilisateur Supabase, créé ici avec une adresse technique jamais utilisée
// (aucun mail n'est envoyé) et un mot de passe aléatoire jamais communiqué.
//
// Peut être appelée par un agent (fiche usager du titulaire) ou par le
// titulaire lui-même (son profil dans l'appli).

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

  const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data: { user: caller }, error: authError } = await callerClient.auth.getUser();
  if (authError || !caller) return json({ ok: false, message: 'Non authentifié' }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  let body: { family_id?: number; full_name?: string; tariff_category?: string };
  try { body = await req.json(); } catch { return json({ ok: false, message: 'Corps de requête invalide' }, 400); }
  const fullName = body.full_name?.trim();
  const tariff = body.tariff_category === 'majeur' ? 'majeur' : 'mineur';
  if (!fullName) return json({ ok: false, message: 'Le prénom et le nom de l\'enfant sont obligatoires.' }, 400);

  const { data: family } = await admin.from('families').select('id, holder_id, commune_id').eq('id', body.family_id ?? 0).single();
  if (!family) return json({ ok: false, message: 'Carte famille introuvable.' }, 404);

  const { data: callerProfile } = await admin.from('profiles').select('role').eq('id', caller.id).single();
  const isAgent = !!callerProfile && ['agent', 'super_admin'].includes(callerProfile.role);
  if (!isAgent && caller.id !== family.holder_id) {
    return json({ ok: false, message: 'Seul le titulaire de la carte famille ou un agent peut ajouter un enfant.' }, 403);
  }

  const { count } = await admin.from('profiles').select('id', { count: 'exact', head: true }).eq('family_id', family.id);
  const { data: commune } = await admin.from('communes').select('family_max_members').eq('id', family.commune_id).single();
  const max = commune?.family_max_members ?? 6;
  if ((count ?? 0) >= max) return json({ ok: false, message: `La carte famille compte déjà ${max} membres (maximum de la médiathèque).` }, 400);

  const { data: holder } = await admin.from('profiles').select('registration_status').eq('id', family.holder_id).single();

  const technicalEmail = `membre-${crypto.randomUUID()}@membres.bligo.app`;
  const randomPassword = crypto.randomUUID() + crypto.randomUUID();
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email: technicalEmail,
    password: randomPassword,
    email_confirm: true,
    user_metadata: { full_name: fullName, account_type: 'officiel', commune_id: String(family.commune_id ?? '') },
  });
  if (createError || !created?.user) return json({ ok: false, message: createError?.message || 'Échec de la création.' }, 400);

  const { data: profile, error: profileError } = await admin.from('profiles').update({
    full_name: fullName,
    account_type: 'officiel',
    commune_id: family.commune_id,
    commune_confirmed: true,
    registration_status: isAgent ? 'valide' : (holder?.registration_status ?? 'pre_inscrit'),
    tariff_category: tariff,
    family_id: family.id,
    managed_by: family.holder_id,
    validated_at: isAgent ? new Date().toISOString() : null,
    validated_by: isAgent ? caller.id : null,
  }).eq('id', created.user.id).select('id, full_name, subscriber_number').single();

  if (profileError) return json({ ok: false, message: 'Compte créé mais fiche non configurée : ' + profileError.message }, 500);
  return json({ ok: true, member: profile });
});
