// Deploy this as an Edge Function named EXACTLY "send-reminders" (Supabase
// dashboard -> Edge Functions -> Deploy a new function -> Via Editor).
//
// This is NOT called by the app or by any user action. It's called once a
// minute by the Supabase Cron job set up in schema.sql ("Calendar — Cron
// job" section), which is the only thing that makes reminders work without
// the app being open at all. The x-cron-secret check below is what stops
// anyone else who finds this function's URL from triggering it themselves.
//
// What it does, every run:
//   1. Rejects the request unless x-cron-secret matches this function's own
//      CRON_SECRET secret.
//   2. Pulls every event (across every user — this uses the service_role
//      key, which intentionally bypasses Row Level Security, since a
//      background job has no single logged-in user) with reminder_enabled
//      = true and reminder_sent_at still null, for today or yesterday's
//      date (covers events just after midnight in any timezone without
//      scanning the whole table).
//   3. Computes each one's actual "send at" moment — event_date +
//      event_time (defaulting to 9:00 AM for all-day events, same
//      convention most calendar apps use) minus reminder_lead_minutes —
//      and keeps only the ones due now. Anything whose actual event time is
//      more than 2 hours in the past is skipped rather than sent — if this
//      job was down for a while, you get a clean slate instead of a
//      backlog of very late notifications.
//   4. For each due event, sends a real Web Push message (RFC 8291/8292,
//      signed with this project's VAPID keys) to every device that user has
//      turned reminders on for, then marks reminder_sent_at so it's never
//      sent twice — including when zero devices are subscribed, so this
//      doesn't recheck the same reminder-less event every minute forever.
//   5. Cleans up push_subscriptions rows the push service reports as gone
//      (410/404 — the user uninstalled, cleared data, etc.).
//
// Required secrets (Edge Functions -> Manage secrets):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  — already present by default
//     on every Supabase project's Edge Functions, no need to add these.
//   VAPID_PUBLIC_KEY_JWK, VAPID_PRIVATE_KEY_JWK — this project's VAPID
//     keypair in JWK form (see README -> "Calendar reminders" for the
//     exact values to paste in).
//   VAPID_SUBJECT — a mailto: or https: URL identifying you, e.g.
//     "mailto:you@example.com" — required by the Web Push spec so a push
//     service can contact you if something's wrong; defaults to a
//     placeholder if unset, but you should set your own.
//   CRON_SECRET — any random string you generate yourself; must exactly
//     match the 'cron_secret' value stored in Supabase Vault by the Cron
//     section of schema.sql.
import { createClient } from 'jsr:@supabase/supabase-js@2'
import * as webpush from 'jsr:@negrel/webpush@0.5.0'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

const STALE_CUTOFF_MS = 2 * 60 * 60 * 1000 // 2 hours
const DEFAULT_ALL_DAY_TIME = '09:00:00'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const cronSecret = Deno.env.get('CRON_SECRET')
  const gotSecret = req.headers.get('x-cron-secret')
  if (!cronSecret || !gotSecret || gotSecret !== cronSecret) {
    return json({ error: 'Unauthorized' }, 401)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const vapidPublicKeyJwk = Deno.env.get('VAPID_PUBLIC_KEY_JWK')
  const vapidPrivateKeyJwk = Deno.env.get('VAPID_PRIVATE_KEY_JWK')
  const vapidSubject = Deno.env.get('VAPID_SUBJECT') || 'mailto:admin@example.com'

  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: 'Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — these should already be set automatically on every Supabase project; check Edge Functions -> Manage secrets.' }, 500)
  }
  if (!vapidPublicKeyJwk || !vapidPrivateKeyJwk) {
    return json({ error: 'Missing VAPID_PUBLIC_KEY_JWK / VAPID_PRIVATE_KEY_JWK secrets — see README -> "Calendar reminders" for the exact values to add.' }, 500)
  }

  let appServer: webpush.ApplicationServer
  try {
    const vapidKeys = await webpush.importVapidKeys(
      { publicKey: JSON.parse(vapidPublicKeyJwk), privateKey: JSON.parse(vapidPrivateKeyJwk) },
      { extractable: false }
    )
    appServer = await webpush.ApplicationServer.new({ contactInformation: vapidSubject, vapidKeys })
  } catch (err) {
    return json({ error: `Could not import VAPID keys — check VAPID_PUBLIC_KEY_JWK/VAPID_PRIVATE_KEY_JWK are set exactly as generated (valid JSON): ${String(err)}` }, 500)
  }

  // service_role bypasses RLS entirely — required here since this job reads
  // and writes reminders across every user, not just one signed-in caller.
  const admin = createClient(supabaseUrl, serviceRoleKey)

  const now = Date.now()
  const todayIso = new Date(now).toISOString().slice(0, 10)
  const yesterdayIso = new Date(now - 24 * 60 * 60 * 1000).toISOString().slice(0, 10)

  const { data: candidates, error: candErr } = await admin
    .from('calendar_events')
    .select('id, user_id, title, description, event_date, event_time, reminder_lead_minutes, share_token')
    .eq('reminder_enabled', true)
    .is('reminder_sent_at', null)
    .in('event_date', [yesterdayIso, todayIso])

  if (candErr) return json({ error: `Could not read due reminders: ${candErr.message}` }, 500)

  const due = (candidates || []).filter((ev) => {
    const timePart = ev.event_time || DEFAULT_ALL_DAY_TIME
    const eventAt = new Date(`${ev.event_date}T${timePart}`).getTime()
    const sendAt = eventAt - (ev.reminder_lead_minutes || 0) * 60000
    return sendAt <= now && eventAt >= now - STALE_CUTOFF_MS
  })

  if (due.length === 0) return json({ sent: 0, checked: (candidates || []).length })

  let sent = 0
  const errors: string[] = []

  for (const ev of due) {
    const { data: subs, error: subErr } = await admin
      .from('push_subscriptions')
      .select('id, endpoint, p256dh, auth_key')
      .eq('user_id', ev.user_id)

    if (subErr) {
      errors.push(`${ev.id}: could not load subscriptions (${subErr.message})`)
      continue
    }

    if (!subs || subs.length === 0) {
      // No device subscribed — mark sent anyway so this event isn't
      // re-checked every minute forever.
      await admin.from('calendar_events').update({ reminder_sent_at: new Date().toISOString() }).eq('id', ev.id)
      continue
    }

    const whenLabel = ev.event_time
      ? new Date(`${ev.event_date}T${ev.event_time}`).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })
      : new Date(`${ev.event_date}T00:00:00`).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
    const messageJson = JSON.stringify({
      title: ev.title || 'Upcoming event',
      body: `${whenLabel}${ev.description ? ' — ' + String(ev.description).slice(0, 120) : ''}`,
      url: ev.share_token ? `/?e=${ev.share_token}` : '/',
      tag: `event-${ev.id}`,
    })

    let anySucceeded = false
    for (const sub of subs) {
      try {
        const subscriber = appServer.subscribe({
          endpoint: sub.endpoint,
          keys: { p256dh: sub.p256dh, auth: sub.auth_key },
        })
        await subscriber.pushTextMessage(messageJson, { ttl: 86400, urgency: webpush.Urgency.High })
        anySucceeded = true
      } catch (err) {
        if (err instanceof webpush.PushMessageError && err.isGone()) {
          // Browser/OS says this subscription no longer exists — clean it up.
          await admin.from('push_subscriptions').delete().eq('id', sub.id)
          continue
        }
        errors.push(`${ev.id} -> ${sub.id}: ${String(err)}`)
      }
    }

    await admin.from('calendar_events').update({ reminder_sent_at: new Date().toISOString() }).eq('id', ev.id)
    if (anySucceeded) sent++
  }

  return json({ sent, checked: due.length, errors: errors.length ? errors : undefined })
})
