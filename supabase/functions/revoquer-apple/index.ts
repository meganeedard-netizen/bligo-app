// BliGO - suppression d'un compte créé avec « Continuer avec Apple » (02/11/2026)
//
// Règle d'Apple : quand un usager supprime un compte ouvert avec Apple,
// l'appli doit aussi révoquer l'accès chez Apple. Juste avant la suppression,
// l'appli redemande la connexion Apple (code d'autorisation à usage unique) ;
// cette fonction échange ce code contre un jeton puis le révoque.
//
// Secrets des Edge Functions : APPLE_PRIVATE_KEY (contenu du fichier .p8 de
// la clé « BliGO Connexion Apple »), APPLE_KEY_ID, APPLE_TEAM_ID, APPLE_CLIENT_ID.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const APPLE_PRIVATE_KEY = Deno.env.get('APPLE_PRIVATE_KEY');
const APPLE_KEY_ID = Deno.env.get('APPLE_KEY_ID');
const APPLE_TEAM_ID = Deno.env.get('APPLE_TEAM_ID');
const APPLE_CLIENT_ID = Deno.env.get('APPLE_CLIENT_ID') ?? 'com.bligo.app';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

// « client_secret » demandé par Apple : un jeton signé avec la clé .p8 (ES256).
async function clientSecret() {
  const pem = APPLE_PRIVATE_KEY!.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const now = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();
  const header = b64url(enc.encode(JSON.stringify({ alg: 'ES256', kid: APPLE_KEY_ID })));
  const payload = b64url(enc.encode(JSON.stringify({
    iss: APPLE_TEAM_ID, iat: now, exp: now + 300, aud: 'https://appleid.apple.com', sub: APPLE_CLIENT_ID,
  })));
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(`${header}.${payload}`));
  return `${header}.${payload}.${b64url(new Uint8Array(signature))}`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data: { user: caller }, error: authError } = await callerClient.auth.getUser();
  if (authError || !caller) return json({ ok: false, message: 'Non authentifié' }, 401);
  if (!APPLE_PRIVATE_KEY || !APPLE_KEY_ID || !APPLE_TEAM_ID) return json({ ok: false, code: 'pas_de_cle' });

  const { authorizationCode } = await req.json().catch(() => ({}));
  if (!authorizationCode) return json({ ok: false, message: 'Code Apple manquant' }, 400);

  const secret = await clientSecret();
  const tokenRes = await fetch('https://appleid.apple.com/auth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: APPLE_CLIENT_ID, client_secret: secret, code: authorizationCode, grant_type: 'authorization_code' }),
  });
  const tokens = await tokenRes.json().catch(() => ({}));
  const token = tokens.refresh_token ?? tokens.access_token;
  if (!token) return json({ ok: false, message: tokens.error ?? 'Échange du code refusé' }, 400);

  const revokeRes = await fetch('https://appleid.apple.com/auth/revoke', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: APPLE_CLIENT_ID, client_secret: secret, token,
      token_type_hint: tokens.refresh_token ? 'refresh_token' : 'access_token',
    }),
  });
  return json({ ok: revokeRes.ok });
});
