// Deploy this as an Edge Function named EXACTLY "get-shared-voice-url"
// (Supabase dashboard -> Edge Functions -> Deploy a new function -> Via
// Editor). Delete whatever template code is there, paste this whole file
// in, then click "Deploy function" — no keys to type in, the service
// role key mentioned below is added automatically by every Supabase
// project.
//
// Why this exists: voice memos live in a PRIVATE Storage bucket
// ("voice-memos") whose access policies only let the file's own owner
// read it (see schema.sql). That's correct for the normal, logged-in
// app — but it means a visitor opening a public share link (who may not
// even be logged in at all) has no way to generate a working signed URL
// for that note's audio themselves; the bucket's own rules would refuse
// them.
//
// This function is the one deliberate, narrow exception. Given a note's
// public share_token AND the exact storage path of one of that note's
// OWN voice memos, it independently re-checks — itself, using the
// service_role key, trusting nothing the caller claims — that the token
// really does resolve to a non-locked note whose `voices` list genuinely
// contains that exact path, and only then mints a short-lived (1 hour)
// signed URL for it. A wrong token, a path that isn't actually one of
// that note's memos, or a locked/unshared note are all refused. This
// can never be used to fetch any other file, on any other note.
//
// No extra secrets to configure — only the SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY that every Edge Function already has by
// default.
import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  let body: any
  try {
    body = await req.json()
  } catch {
    return json({ error: 'Invalid request body' }, 400)
  }
  const token = typeof body?.token === 'string' ? body.token : ''
  const path = typeof body?.path === 'string' ? body.path : ''
  if (!token || !path) return json({ error: 'Missing token or path' }, 400)

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: 'Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — these should already be set automatically on every Supabase project; check Edge Functions -> Manage secrets.' }, 500)
  }

  // service_role bypasses RLS entirely — required here since this is
  // called by logged-out visitors who have no session of their own.
  const admin = createClient(supabaseUrl, serviceRoleKey)

  const { data: note, error: noteErr } = await admin
    .from('notes')
    .select('locked, voices')
    .eq('share_token', token)
    .maybeSingle()

  if (noteErr) return json({ error: noteErr.message }, 500)
  if (!note || note.locked) return json({ error: 'This link is not available.' }, 404)

  const voices = Array.isArray(note.voices) ? note.voices : []
  const belongsToThisNote = voices.some((v: any) => v && v.path === path)
  if (!belongsToThisNote) return json({ error: 'That recording is not part of this note.' }, 404)

  const { data: signed, error: signErr } = await admin.storage
    .from('voice-memos')
    .createSignedUrl(path, 3600)

  if (signErr || !signed) {
    return json({ error: signErr?.message || 'Could not create a signed URL for this recording.' }, 500)
  }

  return json({ signedUrl: signed.signedUrl })
})
