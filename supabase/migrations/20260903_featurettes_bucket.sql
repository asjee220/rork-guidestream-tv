-- featurettes — public storage bucket for the tvOS hero's hosted clips.
--
-- Mirrors title_featurettes: public read, writes service-role only. The
-- bucket is public so AVPlayer can open the object URL with no auth header
-- and no signed-URL expiry; tvOS has no place to put a token on a video
-- request anyway.
--
-- 200MB cap is generous for a 25s 1080p clip (~15MB) and still refuses a
-- whole feature by accident. HLS mime types are allowed so a .m3u8 ladder
-- can be uploaded later without another migration.
--
-- Objects are written by tools/add-featurette.sh with the service-role key.
--
-- Run against project qwxxkubkbanridcqsqjo. Applied 2026-09-03. Additive:
-- no existing bucket, table, column or policy is altered.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'featurettes',
  'featurettes',
  true,
  209715200,
  array['video/mp4', 'video/quicktime', 'application/vnd.apple.mpegurl', 'video/mp2t']
)
on conflict (id) do nothing;

-- Anyone may read an object in this bucket. Writes are not granted to any
-- role here, so only the service role (which bypasses RLS) can upload.
do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'featurettes_public_read'
  ) then
    create policy featurettes_public_read
      on storage.objects
      for select to public
      using (bucket_id = 'featurettes');
  end if;
end $$;
