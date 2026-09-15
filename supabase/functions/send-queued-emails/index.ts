// BliGO — Envoi effectif des e-mails de relance en attente (15/09/2026)
//
// Vide la table email_outbox (remplie par queue_return_reminders(), voir
// sql/add_return_reminders_email.sql) en envoyant chaque mail via Resend.
// Appelée par le cron "send-queued-emails" (pg_cron -> net.http_post),
// jamais depuis le navigateur.
//
// Variables d'environnement requises (Project Settings > Edge Functions > Secrets) :
//   RESEND_API_KEY            clé API Resend (resend.com/api-keys)
//   EMAIL_FROM                adresse d'expédition, ex. "BliGO <relances@bligo.fr>"
//                              (le domaine doit être vérifié dans Resend, voir README.md)
// SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont injectées automatiquement par
// Supabase pour toute Edge Function, pas besoin de les définir à la main.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const EMAIL_FROM = Deno.env.get('EMAIL_FROM') ?? 'BliGO <relances@bligo.fr>';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// Nombre de mails traités par appel — le cron tourne une fois par jour,
// une file plus longue que ça serait traitée sur le prochain appel plutôt
// que de risquer de dépasser les limites de débit de Resend en un seul coup.
const BATCH_SIZE = 100;

Deno.serve(async (req) => {
  if (!RESEND_API_KEY) {
    return new Response(
      JSON.stringify({ error: 'RESEND_API_KEY manquante dans les secrets de la fonction' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: pending, error: fetchError } = await supabase
    .from('email_outbox')
    .select('id, to_email, to_name, subject, body_text')
    .is('sent_at', null)
    .order('created_at', { ascending: true })
    .limit(BATCH_SIZE);

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let sent = 0;
  let failed = 0;

  for (const mail of pending ?? []) {
    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${RESEND_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: EMAIL_FROM,
          to: mail.to_email,
          subject: mail.subject,
          text: mail.body_text,
        }),
      });

      if (res.ok) {
        await supabase
          .from('email_outbox')
          .update({ sent_at: new Date().toISOString(), error: null })
          .eq('id', mail.id);
        sent++;
      } else {
        const detail = await res.text();
        await supabase
          .from('email_outbox')
          .update({ error: `Resend ${res.status}: ${detail}`.slice(0, 500) })
          .eq('id', mail.id);
        failed++;
      }
    } catch (err) {
      await supabase
        .from('email_outbox')
        .update({ error: String(err).slice(0, 500) })
        .eq('id', mail.id);
      failed++;
    }
  }

  return new Response(JSON.stringify({ sent, failed, total: (pending ?? []).length }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
