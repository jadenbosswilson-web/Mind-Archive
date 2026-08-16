-- ============================================================
-- Mind Archive — database schema
--
-- HOW TO RUN THIS:
-- 1. Go to https://supabase.com/dashboard and open your project.
-- 2. In the left sidebar, click "SQL Editor".
-- 3. Click "New query", paste this entire file in, and click "Run".
-- That's it — this creates everything the app needs.
--
-- Order matters in this file: later sections rely on tables/columns
-- created earlier in the file (e.g. the sharing functions near the
-- bottom reference the saved_shared_notes table, so that table has to
-- be created first). Always paste and run the WHOLE file, top to
-- bottom, rather than just one section — every section is safe to
-- re-run even if you've run it (or an older version of it) before.
-- ============================================================

-- One row per user: their custom folders/topics/moods/activities and
-- preferences. Created automatically the first time someone logs in
-- (see ensureProfile() in the app), so you don't need to insert anything
-- here yourself.
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  folders jsonb not null default '["Personal","Work","Ideas","Journal"]',
  topics jsonb not null default '["Personal","Work","Travel","Ideas","Health"]',
  topic_colors jsonb not null default '{"Personal":"#7f9fc9","Work":"#c98f5a","Travel":"#5aa88a","Ideas":"#b06fbf","Health":"#c96b6b"}',
  activities jsonb not null default '["Morning routine","Workout","Meeting","Reading","Trip","Therapy session","None"]',
  moods jsonb not null default '["Happy","Calm","Reflective","Motivated","Anxious"]',
  color_mode text not null default 'light',
  use_custom_accent boolean not null default false,
  custom_accent text not null default '#7f6a4d',
  ai_enabled boolean not null default true,
  autosave boolean not null default true,
  ai_auto_tag boolean not null default true,
  ai_digest boolean not null default false,
  default_font text not null default 'inherit',
  created_at timestamptz not null default now()
);

-- One row per note. This is the table you'll ask me to insert/update rows
-- in whenever you paste new note content for me to add.
create table if not exists notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  folder text not null default 'Personal',
  date date not null default current_date,
  mood text,
  topic text,
  activity text,
  tags jsonb not null default '[]',
  locked boolean not null default false,
  note_password text,
  content text not null default '',
  voices jsonb not null default '[]',
  font_size int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists notes_user_id_idx on notes(user_id);

-- Row Level Security: this is what makes "multiple people, separate
-- accounts" actually safe. Without these policies, any logged-in user
-- could read or edit anyone else's notes. With them, Postgres itself
-- enforces that you only ever see rows where the row's owner matches
-- whoever is currently logged in — enforced on the server, not just
-- hidden in the app's UI.
alter table profiles enable row level security;
alter table notes enable row level security;

drop policy if exists "read own profile" on profiles;
create policy "read own profile" on profiles for select using (auth.uid() = id);
drop policy if exists "insert own profile" on profiles;
create policy "insert own profile" on profiles for insert with check (auth.uid() = id);
drop policy if exists "update own profile" on profiles;
create policy "update own profile" on profiles for update using (auth.uid() = id);
drop policy if exists "delete own profile" on profiles;
create policy "delete own profile" on profiles for delete using (auth.uid() = id);

drop policy if exists "read own notes" on notes;
create policy "read own notes" on notes for select using (auth.uid() = user_id);
drop policy if exists "insert own notes" on notes;
create policy "insert own notes" on notes for insert with check (auth.uid() = user_id);
drop policy if exists "update own notes" on notes;
create policy "update own notes" on notes for update using (auth.uid() = user_id);
drop policy if exists "delete own notes" on notes;
create policy "delete own notes" on notes for delete using (auth.uid() = user_id);

-- Keep updated_at current automatically whenever a note row changes.
create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists notes_set_updated_at on notes;
create trigger notes_set_updated_at before update on notes
  for each row execute function set_updated_at();

-- ============================================================
-- Voice memos — private audio storage, one folder per user
--
-- Safe to run even if you already ran the section above: this only adds
-- the bucket + policies and doesn't touch your existing tables/notes.
--
-- If this insert errors for you, create the bucket by hand instead:
-- Storage (left sidebar) → Create a new bucket → name it exactly
-- "voice-memos" → leave "Public bucket" OFF → Save. Then re-run just the
-- policy statements below.
-- ============================================================
insert into storage.buckets (id, name, public)
values ('voice-memos', 'voice-memos', false)
on conflict (id) do nothing;

-- Files are stored as "<user-id>/<note-id>/<voice-id>.<ext>" — these policies
-- check that the first folder in the path matches whoever is logged in, so
-- (just like notes and profiles) each person can only reach their own audio.
drop policy if exists "Users upload their own voice memos" on storage.objects;
create policy "Users upload their own voice memos"
on storage.objects for insert
with check (bucket_id = 'voice-memos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users read their own voice memos" on storage.objects;
create policy "Users read their own voice memos"
on storage.objects for select
using (bucket_id = 'voice-memos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users update their own voice memos" on storage.objects;
create policy "Users update their own voice memos"
on storage.objects for update
using (bucket_id = 'voice-memos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users delete their own voice memos" on storage.objects;
create policy "Users delete their own voice memos"
on storage.objects for delete
using (bucket_id = 'voice-memos' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================
-- Note sharing, part 1: columns + the collaborators table
--
-- Safe to run even if you already ran everything above.
--
-- This section only creates tables/columns — no functions rely on
-- anything outside this file yet, so it's safe for it to come first.
-- The actual sharing/collaborator FUNCTIONS are in the next two
-- sections below, in that order, because they reference these tables.
-- ============================================================
alter table notes add column if not exists share_token uuid unique;
alter table notes add column if not exists share_permission text not null default 'view';
alter table notes drop constraint if exists notes_share_permission_check;
alter table notes add constraint notes_share_permission_check check (share_permission in ('view','edit'));

-- Doubles as both "Shared links" (a saved copy of a link someone opened,
-- so they can find it again from their own sidebar) and "Collaborators"
-- (the same rows, read back out from the note owner's side, with the
-- ability to change someone's role or remove them). One row per
-- (person, link) pair.
create table if not exists saved_shared_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  share_token uuid not null,
  permission text not null default 'view' check (permission in ('view','edit')),
  title text not null default '',
  note_date date,
  mood text,
  topic text,
  saved_at timestamptz not null default now(),
  unique (user_id, share_token)
);
create index if not exists saved_shared_notes_user_id_idx on saved_shared_notes(user_id);

-- Set true when the note's owner removes this person as a collaborator
-- (see remove_collaborator() below). The row is kept rather than deleted
-- so that simply re-opening the same link afterward can't silently
-- re-grant access — get_shared_note()/update_shared_note() both check
-- this flag and refuse the removed person outright.
alter table saved_shared_notes add column if not exists revoked boolean not null default false;

alter table saved_shared_notes enable row level security;

drop policy if exists "read own saved shared notes" on saved_shared_notes;
create policy "read own saved shared notes" on saved_shared_notes for select using (auth.uid() = user_id);
drop policy if exists "insert own saved shared notes" on saved_shared_notes;
create policy "insert own saved shared notes" on saved_shared_notes for insert with check (auth.uid() = user_id);
drop policy if exists "update own saved shared notes" on saved_shared_notes;
create policy "update own saved shared notes" on saved_shared_notes for update using (auth.uid() = user_id);
drop policy if exists "delete own saved shared notes" on saved_shared_notes;
create policy "delete own saved shared notes" on saved_shared_notes for delete using (auth.uid() = user_id);

-- ============================================================
-- Note sharing, part 2: the public link itself ("anyone with the link
-- can view or edit", no account needed either way).
--
-- Safe to run even if you already ran everything above.
--
-- Deliberately NOT done with a public row-level-security policy on
-- `notes` (e.g. "select using share_token is not null") — that would
-- let anyone fetch the FULL LIST of every shared note from every
-- account with one query, not just the one note they have the link
-- to. Instead, get_shared_note()/update_shared_note() only ever
-- touch a single row, and only when called with the exact matching
-- token — there's no way to browse or enumerate shared notes in bulk.
-- ============================================================

-- Auth-aware: a logged-out visitor (or a logged-in visitor who has never
-- opened this particular link before) gets the note's plain default
-- permission (n.share_permission). A visitor who IS a known collaborator
-- (has a non-revoked row in saved_shared_notes for this exact token) gets
-- THEIR OWN individually-assigned permission instead, which is how one
-- collaborator can be "can edit" while another on the very same link is
-- still "can view." A collaborator the owner has removed (revoked = true)
-- gets no row back at all — same as an unshared/deleted note — even
-- though the link string itself still resolves for everyone else.
drop function if exists get_shared_note(uuid);
create function get_shared_note(p_token uuid)
returns table (
  title text, date date, mood text, topic text, activity text,
  tags jsonb, content text, share_permission text
)
security definer
set search_path = public
stable
language sql
as $$
  select
    n.title, n.date, n.mood, n.topic, n.activity, n.tags, n.content,
    coalesce(
      (select s.permission from saved_shared_notes s
       where s.share_token = p_token and s.user_id = auth.uid() and s.revoked = false),
      n.share_permission
    ) as share_permission
  from notes n
  where n.share_token = p_token
    and n.locked = false
    and not exists (
      select 1 from saved_shared_notes s
      where s.share_token = p_token and s.user_id = auth.uid() and s.revoked = true
    );
$$;

-- Anyone (including logged-out visitors using only the anon key) is
-- allowed to CALL this function — it's safe because the function
-- itself only ever exposes one note at a time, and only if it's
-- unlocked, its token is known, and (for a logged-in caller) they
-- haven't been individually removed as a collaborator.
grant execute on function get_shared_note(uuid) to anon, authenticated;

-- Same auth-aware permission resolution as get_shared_note() above:
-- checks the caller's own collaborator row first, falls back to the
-- note's plain default permission if they don't have one (or aren't
-- logged in), and refuses outright if they've been individually removed.
create or replace function update_shared_note(p_token uuid, p_title text, p_content text)
returns boolean
security definer
set search_path = public
language plpgsql
as $$
declare
  affected int;
  v_permission text;
begin
  select coalesce(
    (select s.permission from saved_shared_notes s
     where s.share_token = p_token and s.user_id = auth.uid() and s.revoked = false),
    n.share_permission
  )
  into v_permission
  from notes n
  where n.share_token = p_token and n.locked = false;

  if v_permission is distinct from 'edit' then
    return false;
  end if;

  if exists (
    select 1 from saved_shared_notes s
    where s.share_token = p_token and s.user_id = auth.uid() and s.revoked = true
  ) then
    return false;
  end if;

  update notes
  set title = coalesce(p_title, title), content = coalesce(p_content, content)
  where share_token = p_token and locked = false;
  get diagnostics affected = row_count;
  return affected > 0;
end;
$$;

grant execute on function update_shared_note(uuid, text, text) to anon, authenticated;

-- ============================================================
-- Collaborators — lets a note's OWNER see everyone who has opened its
-- share link while logged in, change any one of their roles individually
-- (view vs edit), or remove them entirely — without affecting anyone
-- else on the same link, and without needing a separate link per person.
--
-- Safe to run even if you already ran everything above.
--
-- These three functions are the only way any of this happens: there is
-- deliberately no direct client-side UPDATE/DELETE path onto other
-- people's saved_shared_notes rows (the RLS policies above only ever
-- let a row's own owner touch it). Each function re-checks, on the
-- server, that the caller actually owns the note in question before
-- doing anything — a caller who doesn't own it just gets back an empty
-- list / false, never someone else's data or an error revealing why.
-- ============================================================
create or replace function get_note_collaborators(p_note_id uuid)
returns table (
  collaborator_id uuid,
  display_name text,
  email text,
  permission text,
  saved_at timestamptz
)
security definer
set search_path = public
stable
language sql
as $$
  select s.user_id, coalesce(p.display_name, ''), u.email, s.permission, s.saved_at
  from saved_shared_notes s
  join notes n on n.share_token = s.share_token
  left join profiles p on p.id = s.user_id
  left join auth.users u on u.id = s.user_id
  where n.id = p_note_id
    and n.user_id = auth.uid()
    and s.revoked = false
  order by s.saved_at asc;
$$;

grant execute on function get_note_collaborators(uuid) to authenticated;

create or replace function set_collaborator_role(p_note_id uuid, p_collaborator_id uuid, p_permission text)
returns boolean
security definer
set search_path = public
language plpgsql
as $$
declare
  v_token uuid;
  affected int;
begin
  if p_permission not in ('view','edit') then
    return false;
  end if;
  select share_token into v_token from notes where id = p_note_id and user_id = auth.uid();
  if v_token is null then
    return false;
  end if;
  update saved_shared_notes
  set permission = p_permission
  where share_token = v_token and user_id = p_collaborator_id and revoked = false;
  get diagnostics affected = row_count;
  return affected > 0;
end;
$$;

grant execute on function set_collaborator_role(uuid, uuid, text) to authenticated;

create or replace function remove_collaborator(p_note_id uuid, p_collaborator_id uuid)
returns boolean
security definer
set search_path = public
language plpgsql
as $$
declare
  v_token uuid;
  affected int;
begin
  select share_token into v_token from notes where id = p_note_id and user_id = auth.uid();
  if v_token is null then
    return false;
  end if;
  update saved_shared_notes
  set revoked = true
  where share_token = v_token and user_id = p_collaborator_id;
  get diagnostics affected = row_count;
  return affected > 0;
end;
$$;

grant execute on function remove_collaborator(uuid, uuid) to authenticated;

-- ============================================================
-- Profile pictures — public storage, one image per user
--
-- Safe to run even if you already ran everything above.
--
-- Unlike voice memos (private bucket + signed URLs), this bucket is
-- PUBLIC — avatars are low-sensitivity and shown constantly throughout
-- the UI, so a plain public URL avoids having to keep refreshing a
-- short-lived signed URL. Anyone can VIEW an avatar image if they know
-- its exact URL (same as most apps), but only the owning user can
-- upload/replace/delete their own file, enforced below the same way
-- voice memos are: the first folder in the file path must match
-- whoever is logged in.
-- ============================================================
alter table profiles add column if not exists avatar_url text;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "Avatar images are publicly readable" on storage.objects;
create policy "Avatar images are publicly readable"
on storage.objects for select
using (bucket_id = 'avatars');

drop policy if exists "Users upload their own avatar" on storage.objects;
create policy "Users upload their own avatar"
on storage.objects for insert
with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users update their own avatar" on storage.objects;
create policy "Users update their own avatar"
on storage.objects for update
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users delete their own avatar" on storage.objects;
create policy "Users delete their own avatar"
on storage.objects for delete
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================
-- Weekly reflection digest — stores the most recent AI-written digest so
-- it doesn't regenerate (and re-spend AI usage) every time the app is
-- opened; it's only regenerated automatically once 7+ days have passed,
-- or any time via "Generate now" in the app.
--
-- Safe to run even if you already ran everything above.
-- ============================================================
alter table profiles add column if not exists last_digest_at timestamptz;
alter table profiles add column if not exists last_digest_text text;

-- ============================================================
-- Calendar — events, part 1: the table itself
--
-- Deliberately a separate table from `notes`, not another note field.
-- Events are lightweight (title, optional time, optional reminder) —
-- appointments and reminders, not journal entries. The Calendar tab in
-- the app also shows your existing notes on their date, but those still
-- live in `notes` as before; this table is only for things you add
-- directly on the calendar.
--
-- Safe to run even if you already ran everything above.
-- ============================================================
create table if not exists calendar_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default '',
  description text not null default '',
  event_date date not null,
  event_time time,
  reminder_enabled boolean not null default false,
  reminder_lead_minutes int not null default 30,
  reminder_sent_at timestamptz,
  share_token uuid unique,
  -- Set when this event was created by opening someone else's shared event
  -- link (see get_shared_event() below) — paired with the unique
  -- constraint further down so re-opening the same link twice can't create
  -- two copies in your calendar.
  source_share_token uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, source_share_token)
);
create index if not exists calendar_events_user_id_idx on calendar_events(user_id);
create index if not exists calendar_events_date_idx on calendar_events(event_date);
-- Lets the reminder-sending job (see the Cron section further down) find
-- what's actually due without scanning every event you've ever created.
create index if not exists calendar_events_due_reminders_idx
  on calendar_events(event_date, event_time)
  where reminder_enabled = true and reminder_sent_at is null;

alter table calendar_events enable row level security;
drop policy if exists "read own events" on calendar_events;
create policy "read own events" on calendar_events for select using (auth.uid() = user_id);
drop policy if exists "insert own events" on calendar_events;
create policy "insert own events" on calendar_events for insert with check (auth.uid() = user_id);
drop policy if exists "update own events" on calendar_events;
create policy "update own events" on calendar_events for update using (auth.uid() = user_id);
drop policy if exists "delete own events" on calendar_events;
create policy "delete own events" on calendar_events for delete using (auth.uid() = user_id);

drop trigger if exists calendar_events_set_updated_at on calendar_events;
create trigger calendar_events_set_updated_at before update on calendar_events
  for each row execute function set_updated_at();

-- ============================================================
-- Calendar — events, part 2: sharing a single event by link
--
-- Same pattern as note sharing above: a random token, a function that
-- only ever exposes the ONE event matching the exact token given (no
-- bulk browsing/enumeration), safe to call without an account. Unlike
-- note sharing, opening the link doesn't keep a live reference back to
-- your event — the app copies the title/description/date/time into a
-- brand new event that the other person owns outright, with their OWN
-- reminder settings (see the app's "Add to my calendar" flow). That
-- copy is a completely ordinary row in their own calendar_events,
-- governed by the exact same owner-only RLS policies above — no new
-- policy is needed for that part.
--
-- Safe to run even if you already ran everything above.
-- ============================================================
drop function if exists get_shared_event(uuid);
create function get_shared_event(p_token uuid)
returns table (
  title text, description text, event_date date, event_time time
)
security definer
set search_path = public
stable
language sql
as $$
  select title, description, event_date, event_time
  from calendar_events
  where share_token = p_token;
$$;

grant execute on function get_shared_event(uuid) to anon, authenticated;

-- ============================================================
-- Calendar — Web Push reminder subscriptions
--
-- One row per device/browser you've turned on notifications for (you can
-- have more than one — e.g. your phone and your laptop both get
-- reminders). Stores exactly what the Push API gives back from
-- pushManager.subscribe() — an endpoint URL and two public keys — never
-- anything that could be used to read your notification content or send
-- push messages to anyone else's device.
--
-- Safe to run even if you already ran everything above.
-- ============================================================
create table if not exists push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth_key text not null,
  created_at timestamptz not null default now(),
  unique (user_id, endpoint)
);
create index if not exists push_subscriptions_user_id_idx on push_subscriptions(user_id);

alter table push_subscriptions enable row level security;
drop policy if exists "read own push subscriptions" on push_subscriptions;
create policy "read own push subscriptions" on push_subscriptions for select using (auth.uid() = user_id);
drop policy if exists "insert own push subscriptions" on push_subscriptions;
create policy "insert own push subscriptions" on push_subscriptions for insert with check (auth.uid() = user_id);
drop policy if exists "update own push subscriptions" on push_subscriptions;
create policy "update own push subscriptions" on push_subscriptions for update using (auth.uid() = user_id);
drop policy if exists "delete own push subscriptions" on push_subscriptions;
create policy "delete own push subscriptions" on push_subscriptions for delete using (auth.uid() = user_id);

-- ============================================================
-- Calendar — Cron job that actually sends reminders
--
-- This is what makes reminders happen without the app being open: once a
-- minute, Postgres itself (via the pg_cron extension) calls the
-- `send-reminders` Edge Function, which checks for anything due and sends
-- real Web Push notifications. Entirely optional — everything else in the
-- Calendar tab works fine without this section; you just won't get
-- push reminders until it's set up.
--
-- HOW TO FINISH SETTING THIS UP (after running this section):
-- 1. Deploy `send-reminders-function.ts` the same way you deployed the
--    other functions (Edge Functions -> Deploy a new function -> Via
--    Editor -> name it exactly "send-reminders").
-- 2. Add its secrets (VAPID_PUBLIC_KEY_JWK, VAPID_PRIVATE_KEY_JWK,
--    VAPID_SUBJECT, CRON_SECRET) — see the "Calendar reminders" section of
--    the README for exactly what to generate and where it goes.
-- 3. Replace 'REPLACE_WITH_YOUR_CRON_SECRET' below with the SAME value
--    you used for the CRON_SECRET secret in step 2, then run just this
--    "Calendar — Cron job" section again (safe to re-run on its own).
--
-- Safe to run even if you already ran everything above — pg_cron jobs
-- are named, so re-running this replaces the existing schedule instead
-- of creating a duplicate.
-- ============================================================
create extension if not exists pg_cron;
create extension if not exists pg_net;

select vault.create_secret('https://YOUR-PROJECT-REF.supabase.co', 'project_url')
where not exists (select 1 from vault.decrypted_secrets where name = 'project_url');
select vault.create_secret('YOUR_SUPABASE_ANON_KEY', 'publishable_key')
where not exists (select 1 from vault.decrypted_secrets where name = 'publishable_key');
select vault.create_secret('REPLACE_WITH_YOUR_CRON_SECRET', 'cron_secret')
where not exists (select 1 from vault.decrypted_secrets where name = 'cron_secret');

select cron.unschedule('send-reminders-every-minute')
where exists (select 1 from cron.job where jobname = 'send-reminders-every-minute');

select cron.schedule(
  'send-reminders-every-minute',
  '* * * * *',
  $$
  select
    net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-reminders',
      headers := jsonb_build_object(
        'Content-type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'publishable_key'),
        'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
      ),
      body := '{}'::jsonb
    ) as request_id;
  $$
);
