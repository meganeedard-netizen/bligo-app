// BliGO - lecture des photos de livre par l'IA (28/10/2026)
//
// Deux usages, réservés aux agents :
// - mode "resume" : photo de la 4e de couverture -> le résumé recopié mot pour
//   mot (remplace la lecture lettre par lettre de Tesseract, qui laissait
//   beaucoup de fautes) ;
// - mode "couverture" : photo de couverture déjà redressée -> contrôle de
//   qualité (dos du livre, reflet, flou, doigt…). L'image n'est jamais
//   modifiée par l'IA : une IA qui « embellit » redessine les lettres.
//
// Clé : secret ANTHROPIC_API_KEY des Edge Functions. Sans clé, la fonction
// répond { ok:false, code:'pas_de_cle' } et le logiciel garde l'ancien
// fonctionnement.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Anthropic from 'npm:@anthropic-ai/sdk@1.3.0';
import { zodOutputFormat } from 'npm:@anthropic-ai/sdk@1.3.0/helpers/zod';
import { z } from 'npm:zod@4.6.7';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY');

// Modèle léger par défaut (28/10/2026, choix de Mégane pour le coût). Le
// super-admin peut demander le modèle précis pour comparer les deux.
const MODELS = { leger: 'claude-haiku-5-5', precis: 'claude-opus-5-5' } as const;
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}

const ResumeSchema = z.object({
  est_quatrieme_de_couverture: z.boolean(),
  resume: z.string(),
  passages_illisibles: z.boolean(),
  remarque: z.string(),
});

const CouvertureSchema = z.object({
  acceptable: z.boolean(),
  problemes: z.array(z.enum(['dos_du_livre', 'reflet', 'flou', 'trop_sombre', 'doigt_ou_objet', 'couverture_coupee', 'pas_un_livre'])),
  conseil: z.string(),
});

const PROMPT_RESUME = (title: string) => `Cette photo montre la 4e de couverture d'un livre${title ? ` (titre : « ${title} »)` : ''}, prise au téléphone par un agent de médiathèque.

Recopie le texte de présentation du livre (le résumé de l'éditeur) exactement comme il est imprimé : mêmes mots, même ponctuation, accents et majuscules. Recolle les mots coupés en fin de ligne et mets le texte sur un seul paragraphe par paragraphe imprimé (séparés par une ligne vide).

Laisse de côté : prix, ISBN, code-barres, nom et adresse de l'éditeur, crédits photo, mentions de collection, et la courte biographie de l'auteur si elle est séparée du résumé.

N'invente et ne reformule rien. Si un passage est illisible (reflet, flou, coupé), arrête le texte avant ce passage et mets passages_illisibles à true. Si ce n'est pas une 4e de couverture, mets est_quatrieme_de_couverture à false et resume vide. La remarque, en français et en une phrase courte, s'adresse à l'agent (vide si tout va bien).`;

const PROMPT_COUVERTURE = (title: string) => `Cette image est la photo d'une couverture de livre${title ? ` (titre attendu : « ${title} »)` : ''}, prise au téléphone par un agent de médiathèque puis recadrée. Elle sera affichée dans le catalogue de l'appli.

Dis si elle est utilisable. Problèmes possibles :
- dos_du_livre : c'est la 4e de couverture (résumé, code-barres) et non la face avant ;
- reflet : une tache de lumière gêne la lecture du titre ou cache l'illustration ;
- flou : le titre n'est pas net ;
- trop_sombre : l'image est sombre ou terne au point de gêner ;
- doigt_ou_objet : un doigt, une main ou un objet est sur la couverture ;
- couverture_coupee : une partie de la couverture manque, ou on voit le fond autour ;
- pas_un_livre : ce n'est pas une couverture de livre.

Sois raisonnable : un léger défaut qui ne gêne pas la lecture ne compte pas. acceptable vaut false seulement s'il y a au moins un vrai problème. Le conseil, en français, tutoie l'agent et dit en une phrase comment reprendre la photo (vide si elle est acceptable).`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, message: 'Méthode non supportée' }, 405);

  const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data: { user: caller }, error: authError } = await callerClient.auth.getUser();
  if (authError || !caller) return json({ ok: false, message: 'Non authentifié' }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: profile } = await admin.from('profiles').select('role').eq('id', caller.id).maybeSingle();
  if (!['agent', 'super_admin'].includes(profile?.role)) return json({ ok: false, message: 'Réservé aux agents' }, 403);

  if (!ANTHROPIC_API_KEY) return json({ ok: false, code: 'pas_de_cle', message: 'Clé API Anthropic absente' });

  let body: { mode?: string; photo?: string; title?: string; modele?: string };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, message: 'Corps de requête invalide' }, 400);
  }
  const mode = body.mode === 'couverture' ? 'couverture' : 'resume';
  const photo = (body.photo || '').replace(/^data:image\/\w+;base64,/, '');
  if (!photo) return json({ ok: false, message: 'Photo manquante' }, 400);
  if (photo.length * 0.75 > MAX_PHOTO_BYTES) return json({ ok: false, message: 'Photo trop lourde' }, 413);
  const title = String(body.title || '').slice(0, 200);

  const model = body.modele === 'precis' && profile?.role === 'super_admin' ? MODELS.precis : MODELS.leger;
  const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY });
  try {
    const response = await client.messages.parse({
      model,
      max_tokens: 8000,
      output_config: {
        effort: 'low',
        format: zodOutputFormat(mode === 'couverture' ? CouvertureSchema : ResumeSchema),
      },
      messages: [{
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: photo } },
          { type: 'text', text: mode === 'couverture' ? PROMPT_COUVERTURE(title) : PROMPT_RESUME(title) },
        ],
      }],
    });
    if (response.stop_reason === 'refusal' || !response.parsed_output) {
      return json({ ok: false, message: "L'IA n'a pas pu lire cette photo." });
    }
    return json({ ok: true, mode, model, usage: response.usage, ...response.parsed_output });
  } catch (err) {
    if (err instanceof Anthropic.AuthenticationError) return json({ ok: false, code: 'pas_de_cle', message: 'Clé API Anthropic invalide' });
    if (err instanceof Anthropic.RateLimitError) return json({ ok: false, message: 'Trop de demandes, réessaie dans un instant.' });
    if (err instanceof Anthropic.APIError) return json({ ok: false, message: `Service IA indisponible (${err.status ?? 'réseau'})` });
    return json({ ok: false, message: 'Erreur : ' + String(err) }, 500);
  }
});
