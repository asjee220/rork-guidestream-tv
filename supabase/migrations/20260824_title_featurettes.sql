-- title_featurettes — per-title hosted featurette video for the tvOS
-- full-screen hero.
--
-- featurette_url must be HLS .m3u8 or progressive .mp4 playable by
-- AVPlayer. tvOS has no WKWebView, so the YouTube keys in trailer_cache
-- are unusable there. Public read, writes service-role only, mirroring
-- trailer_cache and streaming_releases.
--
-- Run against project qwxxkubkbanridcqsqjo. Additive only: no existing
-- table, column, or policy is altered. IF NOT EXISTS / policy guards keep
-- a re-run safe.

create table if not exists public.title_featurettes (
  id uuid primary key default gen_random_uuid(),
  tmdb_id integer not null,
  media_type text not null default 'tv' check (media_type in ('tv','movie')),
  featurette_url text not null,
  duration_seconds integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tmdb_id, media_type)
);

alter table public.title_featurettes enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'title_featurettes'
      and policyname = 'title_featurettes_public_read'
  ) then
    create policy title_featurettes_public_read
      on public.title_featurettes
      for select to public
      using (true);
  end if;
end $$;

comment on table public.title_featurettes is
  'Per-title hosted featurette video for the tvOS full-screen hero. featurette_url must be HLS .m3u8 or progressive .mp4 playable by AVPlayer. tvOS has no WKWebView, so the YouTube keys in trailer_cache are unusable here. Public read, writes service-role only, mirroring trailer_cache.';
