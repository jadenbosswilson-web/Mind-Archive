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
