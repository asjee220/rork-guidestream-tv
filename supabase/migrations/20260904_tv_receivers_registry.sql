-- Which Apple TVs are signed in on which account, so the phone's cast sheet
-- can tell a reachable TV from one that is signed into a different account.
-- Bonjour discovery knows nothing about accounts, and the play-command topic
-- is owner-only, so without this the phone offers targets it can never reach
-- and the cast fails silently.
create table if not exists public.tv_receivers (
  device_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  name_resolved boolean not null default false,
  app_version text,
  build_number text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists tv_receivers_user_id_idx on public.tv_receivers (user_id);

alter table public.tv_receivers enable row level security;

-- Read is strictly owner-only: one account can never enumerate another
-- household's TV names.
drop policy if exists "tv_receivers owner read" on public.tv_receivers;
create policy "tv_receivers owner read"
  on public.tv_receivers for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "tv_receivers owner insert" on public.tv_receivers;
create policy "tv_receivers owner insert"
  on public.tv_receivers for insert to authenticated
  with check (user_id = auth.uid());

-- Update is deliberately not owner-gated on the EXISTING row: an Apple TV
-- that signs out of one account and into another must be able to re-claim
-- its own device_id, which an owner-only USING clause would block, leaving a
-- stale row that tells the old account the TV is still theirs. WITH CHECK
-- still pins the new owner to the caller, and device_id is a random UUID, so
-- the only row anyone can overwrite in practice is their own TV's.
drop policy if exists "tv_receivers claim" on public.tv_receivers;
create policy "tv_receivers claim"
  on public.tv_receivers for update to authenticated
  using (true)
  with check (user_id = auth.uid());

drop policy if exists "tv_receivers owner delete" on public.tv_receivers;
create policy "tv_receivers owner delete"
  on public.tv_receivers for delete to authenticated
  using (user_id = auth.uid());
