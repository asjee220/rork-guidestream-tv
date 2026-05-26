//
//  SupabaseSetupSQL.swift
//  GuideStreamTV
//
//  Single source of truth for the SQL the user needs to paste into the
//  Supabase SQL Editor to provision the tables, columns, and RLS policies
//  this app expects. Safe to re-run (uses `IF NOT EXISTS` everywhere and
//  drops + recreates policies idempotently).
//

import Foundation

enum SupabaseSetupSQL {
    /// Full schema bootstrap script. Copyable from the diagnostics screen.
    static let script: String = """
    -- =====================================================
    -- GuideStream TV — Supabase Schema Setup
    -- Paste this entire block into the Supabase SQL Editor
    -- and click Run. Safe to re-run.
    -- =====================================================

    -- USERS PROFILE
    create table if not exists public.users (
      id uuid references auth.users on delete cascade primary key,
      display_name text,
      first_name text,
      last_name text,
      avatar_url text,
      email text,
      services text[],
      notify_push boolean default false,
      notify_sms boolean default false,
      created_at timestamptz default now(),
      updated_at timestamptz default now()
    );
    alter table public.users add column if not exists first_name text;
    alter table public.users add column if not exists last_name text;
    alter table public.users add column if not exists email text;
    alter table public.users add column if not exists services text[];
    alter table public.users add column if not exists notify_push boolean default false;
    alter table public.users add column if not exists notify_sms boolean default false;

    alter table public.users enable row level security;
    drop policy if exists "users_read_own" on public.users;
    drop policy if exists "users_insert_own" on public.users;
    drop policy if exists "users_update_own" on public.users;
    create policy "users_read_own" on public.users for select using (auth.uid() = id);
    create policy "users_insert_own" on public.users for insert with check (auth.uid() = id);
    create policy "users_update_own" on public.users for update using (auth.uid() = id);

    -- USER STREAMS (Watch List)
    --
    -- Designed to work for BOTH signed-in users and guests:
    --   * `user_id`   — set for signed-in users (nullable, no FK so guests
    --                   and any non-Supabase-auth id won't be rejected).
    --   * `device_id` — always set; this is the identifier guests use to
    --                   own their list before they sign in.
    create table if not exists public.user_streams (
      id uuid primary key default gen_random_uuid(),
      user_id uuid,
      device_id text,
      title_id text not null,
      title text,
      poster_url text,
      platform text,
      added_at timestamptz default now()
    );
    alter table public.user_streams add column if not exists title text;
    alter table public.user_streams add column if not exists poster_url text;
    alter table public.user_streams add column if not exists platform text;
    alter table public.user_streams add column if not exists device_id text;

    -- Drop the FK to auth.users so guests (no auth row) and any other
    -- non-Supabase-auth id can write. We intentionally leave `user_id`
    -- nullable + un-referenced so the watch list works offline / pre-signin.
    alter table public.user_streams drop constraint if exists user_streams_user_id_fkey;
    alter table public.user_streams alter column user_id drop not null;

    -- Drop legacy NOT NULL constraints from older schema versions so the
    -- app's modern inserts (`title_id` + `title`) succeed. Wrapped in a DO
    -- block so it's a no-op when the legacy columns don't exist.
    do $do$
    begin
      if exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'user_streams'
          and column_name = 'title_name'
      ) then
        execute 'alter table public.user_streams alter column title_name drop not null';
      end if;
      if exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'user_streams'
          and column_name = 'show_id'
      ) then
        execute 'alter table public.user_streams alter column show_id drop not null';
      end if;
    end $do$;

    create index if not exists user_streams_user_idx on public.user_streams(user_id);
    create index if not exists user_streams_device_idx on public.user_streams(device_id);

    -- Old unique index used (user_id, title_id), which fails for guests
    -- whose user_id is NULL. Replace with a partial-unique index per id +
    -- title_id so each ownership lane (user OR device) stays de-duplicated.
    drop index if exists public.user_streams_user_title_uidx;
    create unique index if not exists user_streams_user_title_uidx
      on public.user_streams(user_id, title_id) where user_id is not null;
    create unique index if not exists user_streams_device_title_uidx
      on public.user_streams(device_id, title_id) where device_id is not null;

    -- Permissive RLS — same model as watch_intent_events / device_sessions.
    -- The app filters by user_id/device_id client-side; the watchlist is
    -- non-sensitive and needs to work for unauthenticated devices too.
    alter table public.user_streams enable row level security;
    drop policy if exists "user_streams_read_own" on public.user_streams;
    drop policy if exists "user_streams_insert_own" on public.user_streams;
    drop policy if exists "user_streams_update_own" on public.user_streams;
    drop policy if exists "user_streams_delete_own" on public.user_streams;
    drop policy if exists "user_streams_open" on public.user_streams;
    create policy "user_streams_open"
      on public.user_streams for all
      using (true) with check (true);

    -- WATCH INTENT EVENTS (analytics — guests included)
    create table if not exists public.watch_intent_events (
      id uuid primary key default gen_random_uuid(),
      user_id uuid,
      device_id text,
      event_type text not null,
      title_id text,
      platform_id text,
      metadata jsonb,
      created_at timestamptz default now()
    );
    alter table public.watch_intent_events add column if not exists device_id text;
    alter table public.watch_intent_events add column if not exists platform_id text;
    alter table public.watch_intent_events add column if not exists metadata jsonb;
    alter table public.watch_intent_events add column if not exists user_id uuid;
    alter table public.watch_intent_events add column if not exists title_id text;

    create index if not exists watch_intent_device_idx on public.watch_intent_events(device_id);
    create index if not exists watch_intent_user_idx on public.watch_intent_events(user_id);
    create index if not exists watch_intent_event_idx on public.watch_intent_events(event_type);

    alter table public.watch_intent_events enable row level security;
    drop policy if exists "watch_intent_anyone_insert" on public.watch_intent_events;
    drop policy if exists "watch_intent_read_all" on public.watch_intent_events;
    create policy "watch_intent_anyone_insert"
      on public.watch_intent_events for insert with check (true);
    create policy "watch_intent_read_all"
      on public.watch_intent_events for select using (true);

    -- DEVICE SESSIONS (one row per install — the guest profile)
    create table if not exists public.device_sessions (
      device_id text primary key,
      user_id uuid,
      is_guest boolean,
      is_authenticated boolean,
      email text,
      services text[],
      service_count int,
      notify_push boolean,
      notify_sms boolean,
      onboarding_complete boolean,
      session_count int,
      app_version text,
      build_number text,
      os_version text,
      device_model text,
      first_seen_at timestamptz default now(),
      last_seen_at timestamptz default now()
    );

    alter table public.device_sessions enable row level security;
    drop policy if exists "device_sessions_open" on public.device_sessions;
    create policy "device_sessions_open"
      on public.device_sessions for all
      using (true) with check (true);

    -- NEW EPISODES (read-only on client)
    create table if not exists public.new_episodes (
      id uuid primary key default gen_random_uuid(),
      title_id text not null,
      title text,
      season int,
      episode int,
      duration_minutes int,
      platform text,
      poster_url text,
      is_new boolean default true,
      released_at timestamptz default now()
    );
    alter table public.new_episodes enable row level security;
    drop policy if exists "new_episodes_read_all" on public.new_episodes;
    create policy "new_episodes_read_all"
      on public.new_episodes for select using (true);

    -- TITLE LIKES (one row per (owner, title_id))
    --
    -- Same dual-ownership model as user_streams: signed-in users own rows by
    -- user_id; guests + cross-device installs own rows by device_id. Partial
    -- unique indexes keep each lane de-duplicated so toggle-like is idempotent.
    create table if not exists public.title_likes (
      id uuid primary key default gen_random_uuid(),
      user_id uuid,
      device_id text,
      title_id text not null,
      created_at timestamptz default now()
    );
    alter table public.title_likes add column if not exists user_id uuid;
    alter table public.title_likes add column if not exists device_id text;
    alter table public.title_likes drop constraint if exists title_likes_user_id_fkey;
    alter table public.title_likes alter column user_id drop not null;

    create index if not exists title_likes_title_idx on public.title_likes(title_id);
    create index if not exists title_likes_user_idx on public.title_likes(user_id);
    create index if not exists title_likes_device_idx on public.title_likes(device_id);

    drop index if exists public.title_likes_user_title_uidx;
    drop index if exists public.title_likes_device_title_uidx;
    create unique index if not exists title_likes_user_title_uidx
      on public.title_likes(user_id, title_id) where user_id is not null;
    create unique index if not exists title_likes_device_title_uidx
      on public.title_likes(device_id, title_id) where device_id is not null;

    alter table public.title_likes enable row level security;
    drop policy if exists "title_likes_open" on public.title_likes;
    create policy "title_likes_open"
      on public.title_likes for all
      using (true) with check (true);

    -- TITLE COMMENTS (append-only thread per title_id)
    create table if not exists public.title_comments (
      id uuid primary key default gen_random_uuid(),
      user_id uuid,
      device_id text,
      title_id text not null,
      body text not null,
      display_name text,
      initials text,
      created_at timestamptz default now()
    );
    alter table public.title_comments add column if not exists user_id uuid;
    alter table public.title_comments add column if not exists device_id text;
    alter table public.title_comments add column if not exists display_name text;
    alter table public.title_comments add column if not exists initials text;
    alter table public.title_comments drop constraint if exists title_comments_user_id_fkey;
    alter table public.title_comments alter column user_id drop not null;

    create index if not exists title_comments_title_idx on public.title_comments(title_id);
    create index if not exists title_comments_created_idx on public.title_comments(created_at desc);

    alter table public.title_comments enable row level security;
    drop policy if exists "title_comments_open" on public.title_comments;
    create policy "title_comments_open"
      on public.title_comments for all
      using (true) with check (true);

    -- =====================================================
    -- All set! Re-open the Diagnostics screen in the app and
    -- tap "Re-test" to confirm every table reports OK.
    -- =====================================================
    """

    /// Direct URL to the Supabase SQL Editor for the active project. Lets
    /// the diagnostics screen offer a one-tap "Open SQL Editor" button.
    static func sqlEditorURL() -> URL? {
        // Extract the project ref from `https://qwxxkubkbanridcqsqjo.supabase.co`
        guard let host = URL(string: SupabaseConfig.url)?.host,
              let projectRef = host.split(separator: ".").first else {
            return URL(string: "https://supabase.com/dashboard")
        }
        return URL(string: "https://supabase.com/dashboard/project/\(projectRef)/sql/new")
    }
}
