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
    create table if not exists public.user_streams (
      id uuid primary key default gen_random_uuid(),
      user_id uuid references auth.users on delete cascade,
      title_id text not null,
      title text,
      poster_url text,
      platform text,
      added_at timestamptz default now()
    );
    alter table public.user_streams add column if not exists title text;
    alter table public.user_streams add column if not exists poster_url text;
    alter table public.user_streams add column if not exists platform text;

    -- Drop legacy NOT NULL constraints from older schema versions so the
    -- app's modern inserts (`title_id` + `title`) succeed. Wrapped in a DO
    -- block so it's a no-op when the legacy columns don't exist.
    do $
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
    end $;

    create index if not exists user_streams_user_idx on public.user_streams(user_id);
    create unique index if not exists user_streams_user_title_uidx
      on public.user_streams(user_id, title_id);

    alter table public.user_streams enable row level security;
    drop policy if exists "user_streams_read_own" on public.user_streams;
    drop policy if exists "user_streams_insert_own" on public.user_streams;
    drop policy if exists "user_streams_update_own" on public.user_streams;
    drop policy if exists "user_streams_delete_own" on public.user_streams;
    create policy "user_streams_read_own" on public.user_streams for select using (auth.uid() = user_id);
    create policy "user_streams_insert_own" on public.user_streams for insert with check (auth.uid() = user_id);
    create policy "user_streams_update_own" on public.user_streams for update using (auth.uid() = user_id);
    create policy "user_streams_delete_own" on public.user_streams for delete using (auth.uid() = user_id);

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
