# Mind Archive — deployment & content-update guide

This turns the prototype into a real site: anyone can sign up, log in, and
their notes are private to their account. The files that matter:

- **`mind-archive-app.html`** — the whole site (one file: markup, styles, and logic).
- **`schema.sql`** — creates the database tables and locks them down so each
  person can only ever see their own data.
- **`vercel.json`** — a small config file so Vercel knows to serve
  `mind-archive-app.html` as your homepage (see Part 3).
- **`delete-account-function.ts`** — an optional extra step for 100% real
  account deletion, including your login itself (see "Deleting your account").
- **`README.md`** — this file.

Stack: **Supabase** (free tier) for the database + accounts, and **Vercel**
(free tier) to host the site. Neither requires a credit card to start.

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

1. Open `mind-archive-app.html` in any text editor.
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

### First deploy — no account linking, no command line

1. Go to [vercel.com/drop](https://vercel.com/drop) and sign in (or create a
   free account — Vercel Drop requires one, unlike some other drag-and-drop
   deploy tools).
2. Select **both** `mind-archive-app.html` and `vercel.json` from this folder
   and drag them onto the page together (or drag the whole folder). The
   `vercel.json` file just tells Vercel "show `mind-archive-app.html` when
   someone visits the homepage" — without it, Vercel will ask you to pick a
   homepage instead, which works too, you'd just choose
   `mind-archive-app.html` from the menu it shows you.
3. Give the project a name and click **Deploy**. You'll get a live URL in
   about 10 seconds (like `https://your-project-name.vercel.app`).

### Updating the site later

Here's the one quirk to know: **Vercel Drop always creates a brand-new
project** — dragging the file again doesn't update the live one, it makes a
second site with a different URL. So for any update after the first deploy
(whenever I hand you a new version of `mind-archive-app.html`), use the
**Vercel CLI** instead, which updates the *same* project and keeps your URL:

1. Install [Node.js](https://nodejs.org) if you don't already have it (this
   gives you the `npm` command).
2. Open Terminal (Mac) or Command Prompt/PowerShell (Windows).
3. Run: `npm install -g vercel` (one-time setup).
4. `cd` into the folder with `mind-archive-app.html` and `vercel.json`.
5. Run: `vercel login` and follow the prompt (it'll email you a link).
6. Run: `vercel --prod`. The first time, it'll ask a couple of setup
   questions — accept the defaults. It links this folder to a project and
   deploys it.
7. From then on, whenever I send you an updated `mind-archive-app.html`,
   just replace the file in that folder and run `vercel --prod` again — same
   command, same URL, live in seconds.

*(If you'd rather it auto-deploy from a GitHub repo whenever the file
changes, that's also easy to set up — just let me know and I'll walk you
through connecting a repo instead.)*

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
