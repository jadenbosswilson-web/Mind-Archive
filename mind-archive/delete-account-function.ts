// ============================================================
// OPTIONAL Edge Function: fully removes a user's login (not just
// their data) when they delete their account in Mind Archive.
//
// Why this exists: the app itself only ever uses your "anon" key,
// which can never delete a login — only remove that person's OWN
// data (their notes, voice memos, profile row), which it already
// does. Truly deleting the login/account record requires Supabase's
// admin API, which needs the much more powerful "service_role" key.
// That key must never be placed in the app's own code (anyone could
// read it and delete other people's accounts) — so it has to live
// here instead, inside a server-side function, where Supabase keeps
// it private automatically.
//
// This step is OPTIONAL. Without it, "Delete account" in the app
// still erases 100% of your notes, recordings, and profile data and
// signs you out for good — it just leaves an empty, unusable login
// behind in Supabase's system unless you deploy this too (or delete
// it by hand later, see README).
//
// HOW TO DEPLOY THIS (no coding tools needed, ~2 minutes):
// 1. In your Supabase project, click "Edge Functions" in the left
//    sidebar.
// 2. Click "Deploy a new function" -> "Via Editor".
// 3. Name it exactly:  delete-account
// 4. Delete whatever template code is there, and paste in this
//    entire file instead.
// 5. Click "Deploy function". That's it — no keys to type in, the
//    service role key Supabase mentions below is added automatically.
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing auth header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // Figure out WHO is calling using their own login token — this is what
    // stops anyone from deleting someone else's account. The person being
    // deleted is always whoever is proven to be logged in right now, never
    // something the caller gets to specify.
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user }, error: userErr } = await callerClient.auth.getUser()
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Only this privileged, server-side client (never exposed to the
    // browser) is allowed to actually delete a login.
    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    const { error: deleteErr } = await adminClient.auth.admin.deleteUser(user.id)
    if (deleteErr) {
      return new Response(JSON.stringify({ error: deleteErr.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
