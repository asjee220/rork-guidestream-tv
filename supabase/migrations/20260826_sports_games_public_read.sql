-- GUI-46: notification taps must open a game detail sheet.
--
-- `sports_games` is written by the `sports_poll_and_notify` edge function with
-- the service-role key, so RLS was left enabled with zero policies and the
-- table was never readable from the app. The iOS/Android clients now resolve a
-- push's `game_id` against this table when ESPN's live scoreboard does not
-- contain it (a "Final" push tapped after the slate rolls over, or any tap
-- while ESPN is refusing the request), so the row has to be readable.
--
-- The table holds public scoreboard data only — no user rows, no PII — so this
-- follows the same `<table>_public_read` shape already used for
-- `new_episodes`, `title_names`, `trailer_cache` and friends. Read only:
-- writes stay service-role.

alter table public.sports_games enable row level security;

drop policy if exists sports_games_public_read on public.sports_games;

create policy sports_games_public_read
  on public.sports_games
  for select
  to public
  using (true);
