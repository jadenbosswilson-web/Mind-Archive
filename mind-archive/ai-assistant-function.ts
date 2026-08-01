// ============================================================
// Edge Function: real AI backend for Sainha's Pages — the AI chat tab,
// the per-note "Summarize / Suggest mood & topic / Continue writing /
// Reflect" quick actions, the automatic "Auto-tag mood & topic" feature,
// and the "Weekly reflection digest" all call this, instead of any
// hardcoded/canned text.
//
// Runs on Google's Gemini API, specifically because Gemini has a genuine
// free tier (no credit card, real daily quota) — so this whole feature
// can run at $0/month for personal use. If you outgrow the free daily
// quota, Gemini also has a paid tier the same key can use.
//
// Why this has to live server-side (not just call an AI API directly from
// the app): calling a real AI API requires an API key, and any key placed
// in the app's own code is readable by anyone who opens the site — they
// could copy it and use up your free daily quota (or run up charges, on
// a paid key). Keeping the key here, as a Supabase secret, means it never
// reaches the browser. This function also checks that the caller is
// actually logged in to your app before it will use the key on their
// behalf, for the same reason.
//
// HOW TO DEPLOY THIS (no coding tools needed, ~3 minutes):
// 1. Get a free API key from https://aistudio.google.com/apikey (sign in
//    with any Google account) — click "Create API key." No credit card
//    needed; keys created this way default to the free tier, which is a
//    real daily quota, not an expiring trial.
// 2. In your Supabase project, click "Edge Functions" in the left
//    sidebar -> "Deploy a new function" -> "Via Editor".
// 3. Name it exactly:  ai-assistant
// 4. Delete whatever template code is there, and paste in this entire
//    file instead. Click "Deploy function".
// 5. Still in Edge Functions, click "Manage secrets" (or Project Settings
//    -> Edge Functions -> Secrets) and add one:
//      GEMINI_API_KEY = the key you created in step 1
//    (SUPABASE_URL and SUPABASE_ANON_KEY are already provided
//    automatically — you don't need to add those yourself.)
// 6. That's it — the AI chat tab and the per-note AI actions in the app
//    will start giving real responses immediately, no app redeploy
//    needed.
//
// This step is OPTIONAL, same as the account-deletion function. Without
// it, the AI chat tab and per-note AI actions will show a clear message
// telling you AI isn't set up yet, instead of failing silently or faking
// a response.
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Change this if you'd rather use a different Gemini model — add a
// GEMINI_MODEL secret with the model name (see
// https://ai.google.dev/gemini-api/docs/models for current model names
// and which ones currently have a free tier) to override it without
// touching this code.
const DEFAULT_MODEL = 'gemini-3.5-flash'
const MAX_HISTORY_MESSAGES = 20
const MAX_OUTPUT_TOKENS = 1024
// How long to wait on Gemini before giving up and returning a clear error
// instead of hanging. Comfortably under Supabase's own 150s Edge Function
// wall-clock limit — if we let a slow request ride all the way to that
// limit, Supabase kills the function with NO response sent back at all,
// which is exactly what makes the app look permanently "stuck" instead of
// showing an error.
const AI_TIMEOUT_MS = 25000

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function clip(s: unknown, n = 6000): string {
  return String(s || '').slice(0, n)
}

// Builds the system prompt + message list for each kind of request the
// app can make. Every action is grounded in real content the app sends
// (the actual conversation, the actual note text, the person's actual
// custom mood/topic lists) — nothing here is templated or canned on the
// server side either; the AI genuinely generates every reply.
function buildPrompt(action: string, body: any): { system: string; messages: { role: string; content: string }[] } {
  switch (action) {
    case 'chat': {
      const history = Array.isArray(body.messages) ? body.messages.slice(-MAX_HISTORY_MESSAGES) : []
      return {
        system:
          "You are a warm, thoughtful assistant built into a personal notes and journaling app called Sainha's Pages. Have a genuine, natural back-and-forth conversation: ask follow-up questions where it helps, help the person think out loud or brainstorm, and reply the way a smart, attentive person would in a real conversation. Keep replies conversational — usually just a few sentences — and only go longer if the question genuinely calls for it. You don't have access to the person's actual saved notes unless they paste content into this chat.",
        messages: history.map((m: any) => ({
          role: m.role === 'ai' ? 'assistant' : 'user',
          content: clip(m.text, 4000),
        })),
      }
    }
    case 'chat_summary': {
      const history = Array.isArray(body.messages) ? body.messages : []
      const transcript = history
        .map((m: any) => `${m.role === 'ai' ? 'Assistant' : 'Person'}: ${clip(m.text, 2000)}`)
        .join('\n')
      return {
        system:
          'You summarize conversations into a short, well-written note for someone\'s personal journal. Write 1-3 flowing paragraphs of plain prose — no bullet points, no headers, no "the person said / the assistant said" play-by-play, no quoting the conversation verbatim — that capture the key points, ideas, and conclusions from the conversation below, as if the person were writing a reflective note to themselves afterward.',
        messages: [{ role: 'user', content: `Conversation to summarize:\n\n${transcript}` }],
      }
    }
    case 'note_summarize': {
      return {
        system:
          'You write a short, plain-prose summary (2-3 sentences) of a personal journal/note entry. No bullet points or headers, just natural sentences, written about the entry (not addressed to the person as "you").',
        messages: [{ role: 'user', content: `Summarize this note:\n\n${clip(body.content)}` }],
      }
    }
    case 'note_tag': {
      const moods = Array.isArray(body.moods) ? body.moods : []
      const topics = Array.isArray(body.topics) ? body.topics : []
      return {
        system:
          'You choose the best-fitting mood and topic for a journal entry, strictly from the two lists provided — never invent a new one, never pick something not in the list. Respond with EXACTLY two lines and nothing else, in this exact format:\nMood: <one item from the mood list>\nTopic: <one item from the topic list>',
        messages: [
          {
            role: 'user',
            content: `Mood options: ${moods.join(', ') || '(none configured)'}\nTopic options: ${topics.join(', ') || '(none configured)'}\n\nEntry:\n${clip(body.content)}`,
          },
        ],
      }
    }
    case 'note_continue': {
      return {
        system:
          "You continue a personal journal entry in the same voice, tone, and tense as what's already written. Write 1-3 new sentences that could naturally come next. Don't summarize or restate what's already there, and don't add any preamble like \"Here's a continuation\" — just the continuation text itself.",
        messages: [{ role: 'user', content: `Continue this entry:\n\n${clip(body.content)}` }],
      }
    }
    case 'note_reflect': {
      return {
        system:
          'You compare a current journal entry to an older one from around a year earlier and write one short, genuinely specific reflective paragraph (2-4 sentences) noting what changed, what stayed the same, or what stands out. Write directly to the person ("you"), warmly and specifically — avoid generic, could-apply-to-anyone observations.',
        messages: [
          {
            role: 'user',
            content: `Entry from about a year ago (mood: ${clip(body.pastMood, 60) || 'unknown'}):\n${clip(body.pastContent, 3000)}\n\nCurrent entry (mood: ${clip(body.mood, 60) || 'unknown'}):\n${clip(body.content, 3000)}`,
          },
        ],
      }
    }
    case 'weekly_digest': {
      const notes = Array.isArray(body.notes) ? body.notes.slice(0, 30) : []
      const transcript = notes
        .map((n: any) => `Date: ${clip(n.date, 20)} | Mood: ${clip(n.mood, 40) || 'unset'} | Topic: ${clip(n.topic, 40) || 'unset'}\n${clip(n.content, 800)}`)
        .join('\n---\n')
      return {
        system:
          'You write a warm, specific weekly reflection digest for someone\'s personal journal, based on their notes from the past 7 days. Write 2-4 paragraphs of plain prose (no bullet points, no headers) that notice real patterns: mood trends, recurring topics or threads, tensions, wins, contradictions — written directly to the person ("you"), grounded specifically in the notes given, not generic self-help language. If there truly isn\'t much of a pattern in a short list of notes, say so briefly rather than inventing one.',
        messages: [{ role: 'user', content: `This person's notes from the past 7 days, oldest first:\n\n${transcript}` }],
      }
    }
    default:
      throw new Error('Unknown action: ' + action)
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Missing auth header' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const geminiKey = Deno.env.get('GEMINI_API_KEY')
    const model = Deno.env.get('GEMINI_MODEL') || DEFAULT_MODEL

    // Only someone genuinely logged in to your app can make it past this
    // check — this is what stops a stranger who finds this URL from
    // burning through your free daily quota (or spending your budget, on
    // a paid key).
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const {
      data: { user },
      error: userErr,
    } = await callerClient.auth.getUser()
    if (userErr || !user) return json({ error: 'Unauthorized' }, 401)

    if (!geminiKey) {
      return json(
        { error: "AI isn't set up on this deployment yet — see the \"Turning on real AI\" section of the README." },
        500
      )
    }

    let body: any
    try {
      body = await req.json()
    } catch {
      return json({ error: 'Invalid request body' }, 400)
    }

    const action = body?.action
    if (!action) return json({ error: 'Missing action' }, 400)

    let prompt
    try {
      prompt = buildPrompt(action, body)
    } catch (e) {
      return json({ error: String((e as Error).message || e) }, 400)
    }

    if (prompt.messages.length === 0) {
      return json({ error: 'Nothing to send to the AI yet.' }, 400)
    }

    // Gemini's REST API uses "user"/"model" as role names (not
    // "user"/"assistant" like some other providers), and wants the
    // system prompt as a separate top-level field rather than a message.
    const contents = prompt.messages.map((m) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }],
    }))

    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), AI_TIMEOUT_MS)
    let resp: Response
    try {
      resp = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
        {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            'x-goog-api-key': geminiKey,
          },
          body: JSON.stringify({
            system_instruction: { parts: [{ text: prompt.system }] },
            contents,
            generationConfig: {
              maxOutputTokens: MAX_OUTPUT_TOKENS,
              // Gemini 3.x models default to "medium" thinking (a slower,
              // multi-step internal reasoning pass) when this isn't set at
              // all — real, noticeable latency that isn't needed for any of
              // this app's tasks (chatting, summarizing, tagging,
              // continuing a journal entry, writing a digest). "low"
              // minimizes that latency; older 2.5-series models ignore
              // thinkingLevel and use thinkingBudget instead, which this
              // app doesn't need to set since 2.5 Flash already skips
              // thinking by default when no budget is given.
              thinkingConfig: { thinkingLevel: 'low' },
            },
          }),
          signal: controller.signal,
        }
      )
    } catch (fetchErr) {
      if ((fetchErr as Error)?.name === 'AbortError') {
        return json(
          {
            error: `The AI took longer than ${Math.round(AI_TIMEOUT_MS / 1000)}s to respond, so this gave up rather than leaving you staring at "Thinking…" indefinitely. This is usually Gemini being briefly slow/overloaded — try again. If it happens every time, check Edge Functions → ai-assistant → Logs for details.`,
          },
          504
        )
      }
      return json({ error: `Could not reach Gemini: ${String((fetchErr as Error)?.message || fetchErr)}` }, 502)
    } finally {
      clearTimeout(timeoutId)
    }

    if (!resp.ok) {
      const errText = await resp.text().catch(() => '')
      // A 401/403 here is Google rejecting the GEMINI_API_KEY itself —
      // distinct from this function's OWN 401 earlier (which means the
      // caller isn't logged in to the app). Give the actionable reason up
      // front rather than making the person decode a raw JSON error body.
      if (resp.status === 401 || resp.status === 403) {
        return json(
          {
            error: `Google rejected the Gemini API key (HTTP ${resp.status}) — the GEMINI_API_KEY secret is missing, mistyped, expired, or was created/restricted in a way this function can't use. Get a fresh key from https://aistudio.google.com/apikey (a plain API key, not a Vertex AI/OAuth credential), then replace the GEMINI_API_KEY secret in Supabase → Edge Functions → Manage secrets — delete the old one and re-add it rather than editing in place, in case stray whitespace snuck in on a copy/paste. Raw response: ${clip(errText, 200)}`,
          },
          502
        )
      }
      return json({ error: `AI request failed (${resp.status}): ${clip(errText, 300)}` }, 502)
    }

    const data = await resp.json()
    const candidate = Array.isArray(data.candidates) ? data.candidates[0] : null
    const parts = candidate?.content?.parts
    const text = Array.isArray(parts) ? parts.map((p: any) => p.text || '').join('') : ''

    if (!text) {
      // Most common cause: the response was blocked by Gemini's safety
      // filters rather than actually failing — surface that distinctly
      // rather than a generic "empty response" message.
      const finishReason = candidate?.finishReason
      if (finishReason && finishReason !== 'STOP') {
        return json({ error: `AI did not return a response (reason: ${finishReason}). Try rephrasing.` }, 502)
      }
      return json({ error: 'AI returned an empty response.' }, 502)
    }

    return json({ text })
  } catch (err) {
    return json({ error: String(err) }, 500)
  }
})
