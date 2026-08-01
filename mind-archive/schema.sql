-- ============================================================
-- Mind Archive — database schema
--
-- HOW TO RUN THIS:
-- 1. Go to https://supabase.com/dashboard and open your project.
-- 2. In the left sidebar, click "SQL Editor".
-- 3. Click "New query", paste this entire file in, and click "Run".
-- That's it — this creates everything the app needs.
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
-- Note sharing — real public links ("anyone with the link can view
-- or edit", no account needed either way). The sender picks
-- view-only or editable when they share.
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
alter table notes add column if not exists share_token uuid unique;
alter table notes add column if not exists share_permission text not null default 'view';
alter table notes drop constraint if exists notes_share_permission_check;
alter table notes add constraint notes_share_permission_check check (share_permission in ('view','edit'));

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
  select title, date, mood, topic, activity, tags, content, share_permission
  from notes
  where share_token = p_token and locked = false;
$$;

-- Anyone (including logged-out visitors using only the anon key) is
-- allowed to CALL this function — it's safe because the function
-- itself only ever exposes one note at a time, and only if it's
-- unlocked and its token is known.
grant execute on function get_shared_note(uuid) to anon, authenticated;

-- Lets a visitor with an "edit" link actually save changes back,
-- without ever needing an account. Silently does nothing (returns
-- false) if the note has since been unshared, locked, or switched
-- back to view-only — so a stale/revoked link can't be used to edit.
create or replace function update_shared_note(p_token uuid, p_title text, p_content text)
returns boolean
security definer
set search_path = public
language plpgsql
as $$
declare
  affected int;
begin
  update notes
  set title = coalesce(p_title, title), content = coalesce(p_content, content)
  where share_token = p_token and locked = false and share_permission = 'edit';
  get diagnostics affected = row_count;
  return affected > 0;
end;
$$;

grant execute on function update_shared_note(uuid, text, text) to anon, authenticated;

-- ============================================================
-- Shared Links — when a signed-in user opens someone else's share link
-- (yoursite.com/?n=<token>), it's saved to *their own* account so they can
-- find it again later from the "Shared links" tab in the sidebar, instead
-- of needing to keep the original link around.
--
-- Safe to run even if you already ran everything above.
--
-- This is plain owner-only RLS, same pattern as `notes`/`profiles` — each
-- row is private to the user who saved it (auth.uid() = user_id). Saving a
-- token here doesn't grant any extra access on its own: actually reading
-- or editing the note's content still always goes through
-- get_shared_note()/update_shared_note() above, which independently
-- enforce whether that token is currently valid, unlocked, and (for
-- edits) still set to "Can edit." A stored token whose note gets unshared
-- later just stops resolving — this table doesn't need to know why.
-- ============================================================
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
