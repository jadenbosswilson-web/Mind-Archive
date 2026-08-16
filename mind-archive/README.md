# Sainha's Pages — deployment & content-update guide

This turns the prototype into a real site: anyone can sign up, log in, and
their notes are private to their account. The files that matter:

- **`index.html`** — the whole site (one file: markup, styles, and logic).
  Named `index.html` on purpose — Vercel (and virtually every static host)
  automatically serves a file with this exact name as the homepage, no
  config needed to make that happen.
- **`schema.sql`** — creates the database tables and locks them down so each
  person can only ever see their own data.
- **`vercel.json`** — kept as an empty placeholder file. It's not actually
  needed anymore (see Part 3) now that the site is named `index.html`, but
  it's harmless to leave in your repo if you'd rather not delete it.
- **`manifest.json`, `icon-192.png`, `icon-512.png`, `icon-180.png`, `sw.js`**
  — what makes the site installable as a real standalone app from your
  phone's browser (see "Installing it like an app" below). All five need
  to sit in the same folder as `index.html` when you deploy.
- **`delete-account-function.ts`** — an optional extra step for 100% real
  account deletion, including your login itself (see "Deleting your account").
- **`ai-assistant-function.ts`** — an optional extra step for real AI (the
  chat tab and per-note AI actions) instead of them being turned off (see
  "Turning on real AI").
- **`send-reminders-function.ts`** — an optional extra step for real push
  notification reminders on the Calendar tab (see "Calendar reminders").
- **`README.md`** — this file.

Stack: **Supabase** (free tier) for the database + accounts, and **Vercel**
(free tier) to host the site. Neither requires a credit card to start.

**One-time housekeeping if you have an existing deploy:** the site file is
now named `index.html` instead of `mind-archive-app.html`. In your repo,
delete the old `mind-archive-app.html`, add this `index.html`, and you can
also delete `vercel.json` if you'd like (it's no longer needed at all —
see Part 3). Push, and the site keeps working at the exact same URL. From
here on, every future update will already be named `index.html`, so this
is the last rename you'll need to do.

---

## Part 1 — Create the database (Supabase)

1. Go to [supabase.com](https://supabase.com) and sign up (GitHub or email is fine).
2. Click **New project**. Pick any name, set a database password (save it
   somewhere — you won't need it day-to-day, but keep it), pick the region
   closest to you, and click **Create new project**. Wait ~2 minutes for it
   to finish provisioning.
3. In the left sidebar, click **SQL Editor** → **New query**.
4. Open `schema.sql` from this folder, copy the whole thing, paste it into
   the query box, and click **Run**. You should see "Success. No rows returned."
   This created two tables (`profiles` and `notes`), a private storage bucket
   for voice memo audio, and the security rules that keep everyone's data
   private.
   *(Already ran this before? Just re-run the updated file — it's safe to run
   more than once and only adds the new voice-memo storage bucket/policies.)*
5. In the left sidebar, click **Project Settings** (gear icon) → **API**.
   You'll need two values from this page in a minute:
   - **Project URL** (looks like `https://abcdefgh.supabase.co`)
   - **anon public** key (a long string starting with `eyJ...`)

That's the whole database setup. You won't need to touch Supabase again
except when you and I are adding new note content later (see Part 4).

---

## Part 2 — Connect the site to your database

1. Open `index.html` in any text editor.
2. Near the very top of the `<script>` section, find these two lines:
   ```js
   const SUPABASE_URL = 'YOUR_SUPABASE_PROJECT_URL';
   const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
   ```
3. Replace the two placeholder strings with the **Project URL** and **anon
   public** key you copied in step 5 above. Save the file.

If you skip this step, the site will still load, but it'll show a clear
message on the login screen telling you it isn't connected yet, instead of
silently breaking — so it's easy to tell if you missed it.

**Optional but recommended for real use:** by default, Supabase requires
people to confirm their email before they can log in after signing up. If
you'd rather skip that for a small/casual site, go to **Authentication →
Providers → Email** in Supabase and turn off "Confirm email."

---

## Part 3 — Deploy the site (Vercel)

Because the site is named `index.html`, Vercel (like virtually every static
host) serves it automatically as your homepage — no config file, no
rewrite rule, nothing to get wrong. `vercel.json` used to be required for
this; it isn't anymore, which also means one whole category of "404
NOT_FOUND" problem from earlier versions of this guide simply can't happen
now.

### First deploy — no account linking, no command line

1. Go to [vercel.com/drop](https://vercel.com/drop) and sign in (or create a
   free account — Vercel Drop requires one, unlike some other drag-and-drop
   deploy tools).
2. Drag `index.html` (and the other files in this folder — `manifest.json`,
   the `icon-*.png` files, `sw.js`) onto the page, or drag the whole folder.
3. Give the project a name and click **Deploy**. You'll get a live URL in
   about 10 seconds (like `https://your-project-name.vercel.app`).

### Updating the site later

Here's the one quirk to know: **Vercel Drop always creates a brand-new
project** — dragging the file again doesn't update the live one, it makes a
second site with a different URL. So for any update after the first deploy
(whenever I hand you a new version of `index.html`), use the **Vercel CLI**
instead, which updates the *same* project and keeps your URL:

1. Install [Node.js](https://nodejs.org) if you don't already have it (this
   gives you the `npm` command).
2. Open Terminal (Mac) or Command Prompt/PowerShell (Windows).
3. Run: `npm install -g vercel` (one-time setup).
4. `cd` into the folder with `index.html`.
5. Run: `vercel login` and follow the prompt (it'll email you a link).
6. Run: `vercel --prod`. The first time, it'll ask a couple of setup
   questions — accept the defaults. It links this folder to a project and
   deploys it.
7. From then on, whenever I send you an updated `index.html`, just replace
   the file in that folder and run `vercel --prod` again — same command,
   same URL, live in seconds.

### Or: deploying from a GitHub repo (auto-deploys on every push)

This is what live-updates automatically whenever you push a change — no
CLI commands needed after the first setup:

1. Push this folder's files to a GitHub repo (`index.html` and `schema.sql`
   at minimum).
2. In Vercel: **Add New… → Project**, import that repo.
3. **Framework Preset:** leave it as **Other** (not auto-detected as
   Next.js or anything else).
4. **Root Directory:** point this at whichever folder inside the repo
   actually contains `index.html`.
5. Leave Build Command and Output Directory empty/default, then **Deploy**.

To update the live site later with this method, just push a new commit with
the updated `index.html` — Vercel deploys it automatically.

---

## Installing it like an app (no App Store needed)

The site is now a real installable web app — once it's deployed, anyone
can add it to their phone's home screen and it opens full-screen, with its
own icon, and **no browser address bar or tabs** — visually
indistinguishable from an App Store app. This needs three small files
deployed alongside `index.html` (`manifest.json`, the `icon-*.png`
files, and `sw.js`) — real files, not something baked into the HTML, since
that's what phone browsers actually check for before offering a true
standalone install instead of a plain bookmark.

**Verify it's set up correctly after deploying** by visiting these three
URLs directly (replace with your real domain):
- `https://your-site.vercel.app/manifest.json` — should show JSON text.
- `https://your-site.vercel.app/icon-192.png` — should show the icon image.
- `https://your-site.vercel.app/sw.js` — should show JavaScript text.

If any of those instead show your notes app itself, that file didn't
actually get deployed alongside `index.html` — double check
it's in your repo/deploy folder and redeploy.

**On iPhone/iPad (Safari):** open the site → tap the **Share** button →
**Add to Home Screen**.

**On Android (Chrome):** open the site → tap the **⋮** menu → **Add to
Home screen** (or **Install app**, if Chrome offers it directly).

Either way, launching it from the home screen icon afterward opens
straight into the app with no browser chrome. This isn't listed in the
App Store or Google Play — people install it by visiting your site once,
the same way they'd bookmark it.

**If you added it to your home screen before this update,** remove that
old icon first and re-add it after redeploying — otherwise it'll keep
opening the old, non-standalone version.

---

## Part 4 — Adding and updating notes going forward

This is the workflow you asked for: **you paste content to me, I edit the
underlying data, you don't touch the app's UI yourself.**

Here's how it actually works under the hood: your notes live in the `notes`
table in Supabase, not in a plain file — that's what makes real accounts,
multiple people, and private data possible. So "editing the raw file"
becomes "editing the raw data with SQL," and I'll always hand you a ready-to
paste SQL script — you never need to write SQL yourself.

**The workflow:**

1. You paste me the note content (title, date, mood/topic if you know them,
   body text, etc.) in chat — as messy or as clean as you like.
2. I write a SQL script (an `insert into notes (...) values (...)` statement)
   with your content already filled in.
3. You paste that script into Supabase's **SQL Editor** and click **Run**.
4. Refresh the site — the note is there.

The one thing I'll need from you the first time: **your user ID**, so the
SQL knows which account the note belongs to. To find it: in Supabase, go to
**Authentication → Users**, find your email in the list, and copy the value
in the **UID** column (looks like `a1b2c3d4-...`). Send that to me once and
I'll reuse it for future updates.

**If you'd rather I do the "click Run" step too:** I can run the SQL
directly against your live database myself, in the same chat, if you give me
your project's **service role key** (Settings → API → `service_role` —
*not* the anon key) for that session. That key can bypass the privacy rules
in `schema.sql`, so only share it if you're comfortable with that, and treat
it like a password. If you'd rather not share it, the copy-paste-into-SQL-
Editor method above is just as easy and keeps that key entirely out of our
conversation.

---

## Voice memos (now real)

Recording uses your browser's microphone (you'll get a permission prompt the
first time) and uploads the actual audio to a private Supabase Storage
bucket — one folder per account, so nobody else can reach your recordings.
Playback fetches a short-lived, signed link to the file rather than a public
URL. A few things worth knowing:

- **Requires HTTPS.** Microphone access only works over a secure connection.
  Vercel serves your site over HTTPS automatically, so this just works once
  deployed — but it won't work if you open the HTML file directly from your
  computer's file system.
- If an upload fails (e.g. you went offline mid-recording), the memo shows
  an **"Upload failed — Retry"** button. If you reload the page before
  retrying, the recording itself is gone from memory and you'd need to
  record it again — only successfully-uploaded memos are saved permanently.
- Voice memo audio isn't included in the "paste content to me" workflow in
  Part 4 — that's for text notes. Recording has to happen in the browser.

## Changing your email (now real)

Updating your email in Settings now calls Supabase's real account system
directly. Supabase requires confirming the change via a link it emails you
before it actually takes effect (this is Supabase's own security behavior,
not something the app can skip) — you'll see a message telling you to check
your inbox, and your login email stays the same until you click that link.

## Changing your password (now real)

"Change password" in Settings now asks for your current password, re-checks
it against Supabase directly (the same real check used when deleting a
note), and then calls Supabase's real password-update API. No demo alerts,
no plain-text comparisons.

## Deleting your account (now real)

"Delete account" in Settings asks for your password, re-checks it against
Supabase, then for real:

- deletes every one of your voice memo audio files from Storage,
- deletes every one of your notes,
- deletes your profile row (folders, topics, theme, AI settings, etc.),
- signs you out, everywhere.

That's a complete, genuine wipe of everything you created — not a demo.

**One nuance worth knowing:** a browser-only app like this can never, on its
own, delete the *login itself* (your email/password combination in
Supabase's authentication system) — doing that safely requires a special
"admin" key that must never be placed in code anyone's browser can read,
since that would let a stranger delete other people's accounts too.

So by default, after clicking Delete, your data is 100% gone, but the empty
login technically still exists (someone could sign back in to nothing). Two
ways to close that last gap, whichever you'd prefer:

- **Fully automatic (recommended, ~2 minutes, one-time setup):** deploy the
  included `delete-account-function.ts` as a Supabase Edge Function —
  full copy-paste instructions are inside that file itself (Supabase now
  lets you paste and deploy these right from their dashboard, no coding
  tools needed). Once it's deployed, clicking Delete removes the login too,
  automatically, from then on. Skip this and Delete still works exactly as
  described above — it just quietly skips this one extra bit.
- **Manual, one at a time, no setup:** in Supabase, go to
  **Authentication → Users**, find the account, and click **Delete**. Takes
  a few seconds whenever someone actually deletes their account.

## Sharing notes (now real)

"Share note" generates a genuine public link (like
`https://your-site.vercel.app/?n=<a random id>`) that anyone can open — no
account or login required.

*(This uses a `?n=...` link rather than a `/n/...` path on purpose — the
homepage is the one URL guaranteed to load correctly no matter how a static
site is hosted, so putting the token there instead of in the path means
sharing works with zero extra server configuration, on any host.)*

The Share dialog is now deliberately just a link: click Share, get a
**view-only** link, copy it, send it however you like. There's no
permission picker up front anymore — instead, once someone actually opens
the link while logged in, they show up in the **Collaborators** list right
in that same dialog, and that's where you individually promote a specific
person to "Can edit" (or remove them) — see the next section.

A few things worth knowing either way:

- **Locked notes can't be shared.** If a note has a lock password on it,
  the Share button will tell you to unlock it first — sharing would
  defeat the point of locking it.
- **The link doesn't change every time you open the Share dialog** — it's
  the same link until you click **Stop sharing**, which immediately
  invalidates it for everyone (anyone with the old link gets "this link
  isn't available" from then on, collaborators included).
- **Voice memos aren't included** in a shared note's public view, only the
  title and text content — same as the "paste content to me" workflow in
  Part 4, audio stays account-only for now.
- **A logged-out visitor, or a logged-in person who hasn't opened the
  link before**, always gets the plain view-only default — promoting
  someone to "Can edit" only takes effect once they've opened the link at
  least once (which is how they become a "collaborator" in the first
  place; there's no way to grant edit access to someone who's never
  clicked the link).
- Under the hood: each shared note gets a random token stored in a new
  `share_token` column, plus a `share_permission` column that holds this
  plain default (`schema.sql`). Two database functions handle the public
  page itself: one only ever returns *one* note for the *exact* token
  it's given (no browsing/listing shared notes in bulk), and the other
  only ever updates *one* note, and only if the requester's effective
  permission (see below) is "edit."

## Collaborators (now real)

Every note's Share dialog has a **Collaborators** section listing everyone
who has opened that note's link while logged in — pulled fresh from the
database each time you open the dialog, not cached. For each person you
can:

- **Change their role** — a "Can view" / "Can edit" dropdown right next to
  their name, independent of every other collaborator on the same link.
  One person can be view-only while another has edit access, all from the
  exact same shared URL.
- **Remove them** — the &times; button takes their access away
  completely, immediately, even though the link itself keeps working for
  everyone else. If they still have the link and try to open it again,
  they'll see the same "this link isn't available" message a revoked/
  deleted note would show them — reopening the link can't quietly restore
  access the owner took away.

A collaborator is identified by their display name (falls back to their
email if they haven't set one). Only the note's actual owner can see or
change this list — every one of these actions is re-checked against note
ownership on the server, not just hidden in the UI, the same way
everything else in this app enforces ownership.

Under the hood: the existing `saved_shared_notes` table (see "Shared links
tab" below) doubles as the collaborators table — it already had one row
per person who'd opened a link. This update adds a `revoked` column to it,
plus three new functions: `get_note_collaborators()` (owner-only list),
`set_collaborator_role()`, and `remove_collaborator()`. `get_shared_note()`
and `update_shared_note()` were both updated to check the caller's own row
in that table first (their individually-assigned permission, if any, and
whether they've been revoked) before falling back to the note's plain
default permission — that's the whole mechanism that makes per-person
roles and real removal possible on top of a single shared link.

## Shared links tab (now real)

If someone opens a share link while they're **logged in to their own
account** on this app, it's automatically saved to *their* account too —
under a new **Shared links** item in their sidebar, split into "Can view"
and "Can edit" sections. That way they don't have to keep the original
link around to find the note again later; they can just come back to their
own Shared links tab. Clicking a saved entry re-opens the note (fetching
the current version fresh each time, not a stale copy), and there's a
small **&times;** to remove an entry from their list — that only removes
it from *their* list, it never affects your original note or anyone else's
copy of the link.

A logged-out visitor opening the same link still just sees the plain
public page as before, with no account needed — this feature only applies
to people who happen to be logged in when they click the link. If they
weren't logged in, the shared page shows a "Log in or sign up" link so
they can save it afterward if they create an account.

**Nothing about this changes who can see your notes.** Saving a link to
someone else's Shared links tab only stores the token and a small cached
title/date/mood/topic snapshot in *their own* private, RLS-protected row —
actually opening the note's real content still always goes through the
same `get_shared_note`/`update_shared_note` functions as before, which
independently re-check whether the link is still valid every time. If you
click **Stop sharing** on your end, everyone who'd saved that link
(however many people that is) immediately loses the ability to open it,
same as if they'd never saved it.

## Fixed zoom on open (no more "zoomed in" on load)

The site used to open zoomed in on some phones because Safari/Chrome
auto-zoom the whole page when you tap into a text field with small text,
and this app's inputs use a compact 13px font by design. Rather than making
every input bigger (which would change the look of the whole app), the
page's viewport is now locked to a fixed zoom level, so opening the site or
tapping into any field always shows it at the same, correct size.

## "Remember me" on login (now real)

The login screen has a **"Remember me on this device"** checkbox. Checked
(the default), your session is stored so you stay logged in across visits,
the same as most sites. Unchecked, your session is cleared the moment you
close the tab/app, so the next visit asks you to log in again — useful on a
shared or public device.

**One honest caveat:** on an iPhone/iPad where you've installed this as a
home-screen app (see "Installing it like an app"), iOS itself sometimes
clears a web app's stored data if it hasn't been opened in a while, as a
storage-cleanup measure — this is Apple's own platform behavior, not
something any website's code can fully override. The app already asks the
browser to persist its storage as a best-effort mitigation, and normal daily
use won't trigger it, but if you ever do get logged out despite "Remember
me" being checked, that's most likely why — logging back in is a one-time
inconvenience, not a bug in the checkbox itself.

## Profile pictures (now real)

Settings → Account management now has a **Profile picture** row. Click
**Upload**, choose a JPG, PNG, or WEBP image (up to 5MB), and it's saved
immediately — no need to click "Save settings" for this one, since it's a
distinct action rather than a form field. Your picture then shows up
anywhere your initial-letter avatar used to (the sidebar, etc.), and you can
swap it for a different image or click **Remove** at any time to go back to
the plain letter avatar.

Under the hood: images go into a new public `avatars` bucket in Supabase
Storage, one file per account, with rules (in `schema.sql`) that only ever
let *you* upload, replace, or delete *your own* file — anyone can view an
avatar if they know its exact link (same as most apps' profile pictures),
but nobody but you can change it. This is a public bucket rather than the
private/signed-link setup used for voice memos, since avatars are
low-sensitivity and shown constantly, so there's no benefit to the extra
complexity of expiring links.

**If avatar upload doesn't work yet:** re-run the current `schema.sql`
once in the Supabase SQL Editor — it's safe to run again and only adds the
new `avatar_url` column and `avatars` bucket/policies if they're missing.

## Turning on real AI (chat + per-note actions)

The **AI chat** tab and the four per-note buttons ("Summarize this note,"
"Suggest mood & topic," "Continue writing," "Reflect vs. a year ago") now
call a real AI model (Google's Gemini) for every response — there's no
canned/pattern-matched text left anywhere in the app. Gemini was chosen
specifically because it has a genuine free tier (real daily quota, no
credit card, not just an expiring trial), so this whole feature can run
at $0/month for personal use. This needs one more optional piece
deployed, the same way "Delete account" did:

1. Get a **free** API key from
   [aistudio.google.com/apikey](https://aistudio.google.com/apikey) — sign
   in with any Google account, click "Create API key." No credit card
   needed; keys created this way default to the free tier (a real daily
   quota — check [current limits](https://ai.google.dev/gemini-api/docs/rate-limits)
   — not a trial that expires). If you ever outgrow the free quota, the
   same key can be upgraded to pay-as-you-go in the same Google AI Studio
   account.
2. In Supabase: **Edge Functions** → **Deploy a new function** → **Via
   Editor** → name it exactly `ai-assistant` → paste in the entire contents
   of `ai-assistant-function.ts` → **Deploy function**.
3. Still in Edge Functions, open **Manage secrets** and add one:
   `GEMINI_API_KEY` = the key from step 1.
4. Done — no app redeploy needed. The chat tab and per-note AI buttons
   start giving real responses immediately.

**Already deployed `ai-assistant` before with an `ANTHROPIC_API_KEY`?**
The backend switched from Anthropic's Claude API to Google's Gemini API
(to get a genuine free tier) — go back to Supabase → Edge Functions →
`ai-assistant` → replace the code with the current `ai-assistant-function.ts`
→ **Deploy function** again, then add the new `GEMINI_API_KEY` secret per
step 1/3 above (your old `ANTHROPIC_API_KEY` secret can stay or be removed,
it's just unused now). Also re-run the current `schema.sql` once if you
haven't already (it adds two small columns the weekly digest needs to
save itself — safe to run again).

**Until you do this,** AI features aren't faked or hidden — they show a
plain-language error ("AI isn't set up on this deployment yet...") right
in the chat log or the result area, so it's obvious what's missing rather
than silently doing nothing.

**What "real" means here, plainly stated:**

- The **AI chat** tab is a genuine back-and-forth conversation — it
  remembers what's been said earlier in the same conversation and replies
  accordingly, the same way talking to any AI chat assistant works. It
  does *not* automatically have access to your saved notes; it only knows
  what's in the current chat.
- **"Save as note"** now sends the whole conversation to the AI and asks it
  to write a short, genuinely condensed summary (1-3 plain paragraphs) —
  not the old behavior of pasting every message you typed verbatim into
  the note.
- The four per-note buttons each send that note's actual text to the AI
  and use its actual reply — "Suggest mood & topic" is constrained to only
  ever pick from your own configured mood/topic lists (it can't invent a
  new one), and "Reflect vs. a year ago" only runs if a note from around a
  year earlier genuinely exists in your account.
- **Privacy note:** using any of these sends the relevant text (your chat
  messages, or a note's content) to Google's Gemini API to generate a
  reply — that's inherent to what "real AI" means here, the same as it
  would be for any AI feature in any app. If you'd rather a note never
  leave your account, don't use the AI buttons on it.

**"Auto-tag mood & topic" (Settings → AI) is now real too.** When it's on,
a couple of seconds after you pause typing in a note, the app sends the
note's text to the AI and applies whatever mood/topic it picks — always
constrained to your own configured lists, never something invented — and
shows what it did ("✦ AI auto-tagged this note: Calm · Personal") right
under the editor. It's debounced and only re-checks after a meaningful
amount of new content, so it won't spam the AI while you're mid-sentence.

**"Weekly reflection digest" (Settings → AI) is now real too.** When it's
on, a card at the top of the AI chat tab shows a genuinely AI-written
reflection on your last 7 days of notes — real patterns across mood,
topics, and content, not a template. It writes a new one automatically the
first time you open the AI chat tab after 7+ days have passed since the
last one (checked, not scheduled — there's no background job running
while the app is closed), and there's also a "Generate now" button if you
don't want to wait. The digest and its date are saved to your account so
it isn't regenerated (and re-billed) every time you just open the app.

## Calendar (now real)

A **Calendar** tab in the sidebar shows a month grid — click any day to see
what's on it and add something. A few things worth knowing about how it
actually works, all genuinely functional, nothing faked:

- **Notes and events both show up on their date, but they're not the same
  thing.** Your existing notes still live in the `notes` table exactly as
  before (the Calendar tab just displays them on their date alongside
  anything else that day) — this doesn't turn notes into a calendar-only
  concept. **Events** are new, lighter-weight rows in their own
  `calendar_events` table: a title, an optional time, an optional
  description, and an optional reminder. Use a note for a journal-style
  entry, an event for an appointment/reminder.
- **Month/year navigation** — the arrows step one month at a time, the two
  dropdowns jump straight to any month/year, and **Today** snaps back to
  the current date.
- **Holidays are marked automatically** using the free
  [date.nager.at](https://date.nager.at) public holiday API (US holidays,
  no API key or account needed) — no setup required, and if that API is
  ever briefly unreachable, the rest of the Calendar tab keeps working
  fine, it just won't show holiday names until it's reachable again.
- **Adding/editing an event** happens in a small form (title, date, time,
  notes, reminder toggle) reached either by clicking a day or the **+ New
  event** button. Unlike notes, saving an event uses an explicit **Save**
  button rather than autosave-as-you-type, since it's a short form, not
  free-flowing writing.
- **Sharing an event** works like sharing a note: click **Share** inside an
  event, get a link (`https://your-site.vercel.app/?e=<a random id>`),
  send it however you like. The difference from note sharing: opening the
  link doesn't give someone live access to *your* event — clicking **Add
  to my calendar** copies it into a brand-new event *they* own outright,
  with their own independent reminder settings. Re-opening the same link
  again later just updates that same copy rather than creating a
  duplicate.

### Calendar reminders (real push notifications to your phone/browser)

Turning on reminders sends a genuine push notification — the kind that
shows up even if the site/app isn't open — using the **Web Push** standard
(the same underlying protocol every major site uses for this, not a fake
in-app-only reminder). This needs one more optional piece deployed, similar
to AI and account deletion above, plus a database step:

1. **Get this app's VAPID keys** (the credentials that let this specific
   deployment sign push messages) — I'll paste you the exact `publicKey`
   and `privateKey` JWK values to use in chat. Keep the private one out of
   any file you don't fully control; it only ever goes into a Supabase
   secret, never into `index.html` or anything committed to a repo.
2. In Supabase: **Edge Functions** → **Deploy a new function** → **Via
   Editor** → name it exactly `send-reminders` → paste in the entire
   contents of `send-reminders-function.ts` → **Deploy function**.
3. Still in Edge Functions, open **Manage secrets** and add:
   - `VAPID_PUBLIC_KEY_JWK` — the public key JSON I gave you in step 1.
   - `VAPID_PRIVATE_KEY_JWK` — the private key JSON I gave you in step 1.
   - `VAPID_SUBJECT` — `mailto:` followed by any email of yours (required
     by the Web Push standard so a push provider can contact you if
     something's misbehaving; it's never shown to users).
   - `CRON_SECRET` — make up any long random string yourself (e.g. mash the
     keyboard for 30+ characters) — this is what stops anyone else who
     finds this function's URL from triggering it. Remember it for step 4.
4. Back in the **SQL Editor**, open the current `schema.sql`, find the
   `-- Calendar — Cron job` section near the bottom, replace
   `REPLACE_WITH_YOUR_CRON_SECRET` with the *same* random string you just
   used for `CRON_SECRET` in step 3, and run just that section (safe to
   run on its own, and safe to re-run later if you ever rotate the
   secret). This tells Postgres itself to call `send-reminders` once a
   minute, forever, with no server of your own needed.
5. Done. From then on, anyone who clicks **Turn on reminders** above the
   calendar grid (this asks for notification permission, same as any
   site) will get a real notification for any event with reminders turned
   on, at however many minutes/hours/days early they picked in that
   event's form — even with the site closed, even with their phone
   locked, as long as their browser/OS has notifications enabled for it.

**Until step 2-4 are done,** the **Turn on reminders** button and the
reminder toggle on events still work and save normally — you just won't
receive an actual notification when the time comes, since nothing is
running the sending side yet.

**A couple of honest platform notes, not bugs in this app:**
- **iOS/iPadOS requires the site to be installed to your home screen first**
  (see "Installing it like an app" above) before push notifications work
  at all — this is Apple's own restriction on Safari/WebKit, not something
  any website's code can change.
- Reminders are per-device, not per-account — turning them on in one
  browser/phone doesn't automatically turn them on everywhere else you're
  logged in; each device you want reminders on needs its own **Turn on
  reminders** click.

## What's "casual use" vs. "real security" here

Based on what you told me you needed:

- **Account login** (your email + password) is handled entirely by
  Supabase's real authentication system — passwords are properly hashed,
  never stored in plain text, and never seen by the app itself. Deleting a
  note, changing your password, and deleting your account all re-check your
  real password against Supabase directly first.
- **Per-note lock passwords** (the "lock this note" feature) are a much
  lighter, casual gate — they're stored as plain text in the notes table.
  That's fine for hiding a note from a quick glance, but don't reuse an
  important password for it, and don't treat it as real encryption.
- **Multiple accounts** are fully separated at the database level (Row Level
  Security in `schema.sql`), so one person genuinely cannot query or see
  another person's notes, even by tampering with the app in their browser.
  The same separation applies to voice memo audio in Storage.

## Known limitations (flag these if they matter to you)

- **Full login removal on account deletion** requires the optional one-time
  Edge Function step above — without it, your data is fully wiped but the
  empty login record needs a manual delete in the Supabase dashboard (also
  described above). Every other piece of "Delete account" is fully real.
- I've tested all of this thoroughly against a simulated backend, but not
  yet against your actual live Supabase project (I don't have a way to
  create one myself, and my sandbox can't reach outside domains to check).
  The first time you deploy, it's worth signing up, adding a note, recording
  a voice memo, refreshing the page, and confirming it's all still there —
  I'm glad to debug anything that comes up.

## Troubleshooting

- **"This site needs to be connected to a database first"** — you haven't
  replaced the placeholder values in Part 2, or saved the file before
  deploying.
- **"Could not connect to the backend"** — usually a typo'd URL/key, an ad
  blocker blocking the Supabase request, or no internet connection.
- **Signed up but nothing happens** — check if "Confirm email" is turned on
  in Supabase (Part 2); you'd need to click the link in the confirmation
  email before logging in.
- **Microphone permission denied / no recording** — check your browser's
  site settings for microphone access, and make sure you're on the deployed
  HTTPS site, not a local file.
- **"Upload failed" on a voice memo** — usually a dropped connection
  mid-upload; click Retry. If the storage bucket/policies from `schema.sql`
  weren't run, uploads will fail every time — re-run `schema.sql` to check.
- **"Delete account" doesn't fully clear your profile settings** — this
  update added one new security rule to `schema.sql` (permission to delete
  your own profile row). If you set up your database before today, re-run
  the current `schema.sql` once in the SQL Editor — it's safe to run again
  and only adds what's missing.
- **A shared note link says "This link isn't available" even though you
  just shared it** — re-run the current `schema.sql` once (it adds the
  `share_token`/`share_permission` columns and the functions that serve
  and save shared notes; if your database was set up before this update,
  that piece is missing).
- **The homepage itself 404s** — make sure the file is actually named
  `index.html` (not `mind-archive-app.html` or anything else) in your
  repo/deploy folder — that exact name is what makes Vercel serve it as
  the homepage automatically, with no config needed. Then re-deploy (push
  again, or **Deployments → ⋯ → Redeploy**).
- **A shared note link 404s** — shared links now use `?n=...` on the
  homepage rather than a `/n/...` path, specifically so this can't happen
  regardless of hosting config. If you're testing an old `/n/...` link
  from before this update, generate a fresh one from the Share dialog.
- **"Add to Home Screen" still shows browser tabs/address bar instead of
  opening as a standalone app** — this means `manifest.json`, the
  `icon-*.png` files, or `sw.js` aren't actually being served (see the
  three verification URLs in "Installing it like an app" above to check
  which one). Also make sure you removed any home screen icon you added
  *before* this update and re-added it fresh afterward — an old icon
  keeps pointing at the old version.
- **"Can edit" link loads fine but Save changes doesn't stick** — usually
  means `schema.sql` hasn't been re-run since this update (the
  `update_shared_note` function doesn't exist yet), or that person's role
  was changed back to "Can view" (or they were removed, or the note was
  unshared) from the Collaborators list after the link was sent out.
- **Opening a shared link doesn't show up under "Shared links" in the
  sidebar** — re-run the current `schema.sql` once (it adds the
  `saved_shared_notes` table this feature needs; if your database was set
  up before this update, that piece is missing). Also double check you
  were actually logged in when you opened the link — logged-out visitors
  see the plain public page and nothing gets saved, by design.
- **Uploading a profile picture fails or nothing happens** — re-run the
  current `schema.sql` once (it adds the `avatar_url` column and the public
  `avatars` storage bucket/policies; if your database was set up before this
  update, that piece is missing). Also double-check the image is a JPG,
  PNG, or WEBP under 5MB.
- **The Collaborators list in the Share dialog is empty, or "Could not
  load collaborators"** — re-run the current `schema.sql` once (it adds
  the `revoked` column and the `get_note_collaborators`/
  `set_collaborator_role`/`remove_collaborator` functions this needs; if
  your database was set up before this update, that piece is missing).
  Otherwise, remember the list only ever shows people who have actually
  opened the link while logged in — an empty list right after sharing is
  expected until someone does.
- **Changed someone's role or removed them, but it doesn't seem to take
  effect** — the change applies the next time they (re)open the link, not
  to a page they already have open in their browser; ask them to refresh.
- **Still getting logged out despite "Remember me" being checked, on an
  installed home-screen app on iPhone/iPad** — this is iOS's own storage
  cleanup behavior for installed web apps, not the checkbox failing; see
  "Remember me on login" above.
- **AI chat or the per-note AI buttons say "AI isn't set up on this
  deployment yet"** — expected until you deploy `ai-assistant-function.ts`
  and add your `GEMINI_API_KEY` secret; see "Turning on real AI" above.
- **AI chat/actions say "Unauthorized"** — you're not logged in to the app
  (or your session expired); log back in and try again. This is a
  different 401 than the one below — it comes from this app's own check,
  before your request ever reaches Gemini.
- **"Google rejected the Gemini API key" / "AI request failed (401/403)"
  / a raw `{"message":"Invalid credentials","code":"INVALID_CREDENTIALS"}`
  body** — all the same underlying problem: Google itself is rejecting the
  `GEMINI_API_KEY` secret, not this app's code. In order of how often each
  turns out to be the cause:
  1. **The secret has a typo or stray whitespace.** A trailing space or
     newline from copy/pasting is invisible but breaks the key. Don't edit
     the existing secret in place — delete it and add it fresh instead, in
     Supabase → Edge Functions → Manage secrets.
  2. **The key was deleted or revoked** in
     [Google AI Studio](https://aistudio.google.com/apikey) — generate a
     new one and replace the secret the same way.
  3. **It's the wrong kind of key.** This app expects a plain API key from
     [aistudio.google.com/apikey](https://aistudio.google.com/apikey), not
     a Vertex AI/OAuth service-account credential from Google Cloud
     Console — those need different authentication entirely and won't
     work here.
  4. **The key has restrictions attached** (e.g. an HTTP referrer
     restriction) from being created in Google Cloud Console rather than
     AI Studio directly — those restrictions expect requests from a
     browser, not a server, and will reject this function's requests
     even though the key itself is otherwise valid. Create an
     unrestricted key via AI Studio instead.
- **AI chat/actions get stuck on "Thinking…" and never respond** — this
  was a real bug, fixed as of this update, in three layers (all included
  in the current `ai-assistant-function.ts` and `index.html` — **all three
  only take effect once BOTH files are re-deployed**, the function in
  Supabase and the site itself):
  1. The request to Gemini now asks for a lower "thinking" effort. Gemini's
     newer models do an internal multi-step reasoning pass by default
     before answering, which isn't needed for any of this app's tasks
     (chatting, summarizing, tagging, continuing a journal entry) and was
     adding real, avoidable latency.
  2. The function gives up on its own Gemini request after 25 seconds
     with a clear error, instead of ever waiting indefinitely on Google.
  3. The function *as a whole* also gives up after 32 seconds if
     anything — not just the Gemini call — is stalling, e.g. the check for
     who's calling (via Supabase's own auth), which the 25-second timeout
     above doesn't cover on its own. The app itself adds one more backstop
     on top of that (35s) in case a response somehow never comes back at
     all.
  If you're still seeing this after re-deploying both files, the request
  is stalling for close to the full 25-32 seconds every time rather than
  hanging forever — which is a real, ongoing slowness somewhere, not a
  missing timeout anymore. **Check Edge Functions → ai-assistant → Logs**
  in Supabase right after triggering an AI action: the newest entry will
  show whether it's stuck before Gemini (the auth check, most likely a
  Supabase-side hiccup) or genuinely waiting that long on Gemini itself
  (worth trying a different `GEMINI_MODEL` secret, e.g. `gemini-2.5-flash`,
  to see if it's specific to the 3.5 model).
- **"AI request failed (429)"** — you've hit Gemini's free-tier daily/
  per-minute quota. It resets on its own (daily quotas reset at midnight
  Pacific time); see [current limits](https://ai.google.dev/gemini-api/docs/rate-limits).
  This is expected occasionally on the free tier under heavy use, not a
  bug — if it happens often, you can upgrade the same key to pay-as-you-go
  in Google AI Studio.
- **"Could not [do X]: Failed to send a request to the Edge Function"** —
  different from the two errors above: this means the browser couldn't
  reach the function at all (no response came back, not even an error
  one), so it happens for *every* AI feature at once (chat, per-note
  buttons, auto-tag, digest), not just one. In order of how often each
  turns out to be the cause:
  1. **The function isn't deployed yet, or isn't named exactly
     `ai-assistant`.** In Supabase → Edge Functions, confirm it's listed
     with that exact name (case-sensitive, no typos, no extra spaces). If
     it's missing, deploy it per "Turning on real AI" above.
  2. **Wrong project.** If you've ever created more than one Supabase
     project, double-check the `SUPABASE_URL`/`SUPABASE_ANON_KEY` values
     near the top of `index.html` point to the *same* project
     where you deployed `ai-assistant` — it's an easy mismatch if you
     copied a URL from an older project along the way.
  3. **An ad blocker or privacy extension is blocking the request.** Some
     block anything with "functions" in the URL. Try again in a private/
     incognito window with extensions off.
  4. Still stuck? Open your browser's DevTools → **Network** tab, trigger
     the action again, find the request to `.../functions/v1/ai-assistant`,
     and check what it actually says (a CORS error, a DNS failure, a
     timeout) — that pins down which of the above it is.
- **Every AI feature says "Edge Function returned a non-2xx status
  code"** — different again from the error above: this one means the
  function *was* reached and *did* respond, just with an error. This
  exact generic sentence is Supabase's own client library's fixed,
  built-in wording for that situation — it's not coming from this app's
  code, and it deliberately doesn't say *why* the function errored, only
  *that* it did. Reading the real reason back out of that response has
  been unreliable across versions of Supabase's client library, so if
  you're on an older deployed copy of `index.html`, you may only ever see
  this generic sentence no matter what actually went wrong underneath —
  re-deploy the current `index.html`, which reads the real error a few
  different ways and will show you the specific reason (missing/invalid
  key, rate limit, bad model name, etc.) instead of this sentence going
  forward. Either way, the one place that *always* has the real reason,
  unaffected by any of this, is **Supabase → Edge Functions →
  `ai-assistant` → Logs** — open it, trigger the AI action again, and the
  newest log entry will show exactly what happened server-side.
- **Auto-tag never seems to run, or the weekly digest card doesn't show
  up** — check the two switches are actually on in Settings → AI (and
  Save settings clicked), and that AI itself is enabled. The digest card
  only appears on the AI chat tab. If it still doesn't work, re-deploy the
  current `ai-assistant-function.ts` and re-run the current `schema.sql`
  — both changed to support these two features (see "Turning on real AI").
- **The Calendar tab is missing, or events/holidays don't show up** —
  re-run the current `schema.sql` once in the SQL Editor — it's safe to
  run again and only adds the `calendar_events` and `push_subscriptions`
  tables and their functions if they're missing.
- **Holidays never show up on the calendar grid** — check your browser's
  console for a failed request to `date.nager.at` (an ad blocker or
  restrictive network can occasionally block it); the rest of the
  Calendar tab works fine either way, this only affects the holiday
  labels/highlighting.
- **A shared event link says "This link isn't available"** — the event was
  unshared (Stop sharing) or deleted, or you're testing a stale link from
  before re-sharing it — generate a fresh one from that event's Share
  button.
- **"Add to my calendar" on a shared event does nothing or errors** — you
  need to be logged in for this (a logged-out visitor sees a "Log in or
  sign up" link instead of the button); also re-run the current
  `schema.sql` if you haven't already, since this needs the
  `calendar_events` table's `source_share_token` column and unique
  constraint.
- **"Turn on reminders" button does nothing, or reminders never actually
  arrive** — first check you're on a browser that supports push
  (recent Chrome/Edge/Firefox, or an iPhone/iPad *installed to the home
  screen first*, per Apple's own restriction — see "Calendar reminders"
  above). If the button itself works (asks for permission, changes to
  "Reminders on") but notifications never arrive at the actual time, the
  `send-reminders` Edge Function + Cron job likely aren't deployed yet —
  that's an optional extra step, see "Calendar reminders" above; events
  and their reminder settings still save normally without it, they just
  won't be delivered.
- **Reminders worked before but suddenly stopped** — in Supabase, check
  **Database → Cron** (or `select * from cron.job;` in the SQL Editor) to
  confirm the `send-reminders-every-minute` job still exists and its
  recent runs succeeded; also check **Edge Functions → send-reminders →
  Logs** for errors (an expired/rotated `CRON_SECRET` mismatch between
  the Vault value and the function's own secret is the most common cause
  — see step 3/4 of "Calendar reminders" to fix).
