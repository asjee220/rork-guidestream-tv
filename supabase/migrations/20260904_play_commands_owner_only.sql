-- Play on TV command channel: own topic only, signed in only.
--
-- The previous policies granted anon and authenticated read+write on every
-- topic matching 'play-commands:%'. That made 'play-commands:guest' a single
-- world-shared channel, and let any signed-in user broadcast into any other
-- user's topic by naming their uid. Both sides now have to be the owner.
--
-- The clients build the topic from uuidString, which is uppercase, so the
-- comparison is case-folded.

drop policy if exists "play_commands broadcast read"  on realtime.messages;
drop policy if exists "play_commands broadcast write" on realtime.messages;

create policy "play_commands broadcast read"
  on realtime.messages
  for select
  to authenticated
  using (
    extension = 'broadcast'
    and lower((select realtime.topic())) = 'play-commands:' || lower(auth.uid()::text)
  );

create policy "play_commands broadcast write"
  on realtime.messages
  for insert
  to authenticated
  with check (
    extension = 'broadcast'
    and lower((select realtime.topic())) = 'play-commands:' || lower(auth.uid()::text)
  );
