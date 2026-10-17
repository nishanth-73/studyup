-- StudyUp Community backend (Supabase/Postgres).
--
-- Pairs with the local-first Flutter implementation in
-- lib/features/community. Until this migration is applied and the
-- Flutter app is pointed at a Supabase project, Community runs on-device
-- (invite-code snapshots, local rooms/challenges) and all cross-device
-- features are honestly gated in the UI.
--
-- SAFE: creates new tables only; touches no existing data (the app
-- currently stores everything in SharedPreferences, so there is nothing
-- to migrate row-wise). Re-running is safe (IF NOT EXISTS + policy drops
-- + OR REPLACE).
--
-- ORDERING MATTERS: PostgreSQL analyzes LANGUAGE SQL function bodies and
-- policy expressions at CREATE time, so every table is created BEFORE
-- any function, policy, or trigger that references it. Run this file
-- first, then 20261102_social_backend.sql.
-- Requires the pgcrypto extension for gen_random_uuid() (pre-installed
-- on Supabase; created here for self-hosted safety).

create extension if not exists pgcrypto;

-- ================= tables (all of them, first) =================

create table if not exists public.community_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 48),
  avatar_id text not null default 'robo-default',
  blob_variant integer not null default 0,
  leaderboard_opt_in boolean not null default true,
  share_live_status boolean not null default false,
  share_subject boolean not null default false,
  updated_at timestamptz not null default now()
);

create index if not exists community_profiles_name_idx
  on public.community_profiles (display_name);

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references auth.users (id) on delete cascade,
  to_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at timestamptz not null default now(),
  check (from_id <> to_id)
);

create unique index if not exists friend_requests_open_pair_idx
  on public.friend_requests (least(from_id, to_id), greatest(from_id, to_id))
  where status = 'pending';

create index if not exists friend_requests_to_idx
  on public.friend_requests (to_id, status);

create table if not exists public.friendships (
  user_low uuid not null references auth.users (id) on delete cascade,
  user_high uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_low, user_high),
  check (user_low < user_high)
);

create index if not exists friendships_user_idx
  on public.friendships (user_low, user_high);

alter table public.community_profiles enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;

-- ================= helpers (after the tables they read) =================
-- NOTE: language sql bodies are validated at CREATE time, so this must
-- stay below the friendships table. Do not move it above.

create or replace function public.community_are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friendships f
    where (f.user_low = least(a, b) and f.user_high = greatest(a, b))
  );
$$;

-- ================= profiles policies =================

drop policy if exists "own profile full access" on public.community_profiles;
create policy "own profile full access"
  on public.community_profiles
  for all
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "friends read public profile" on public.community_profiles;
create policy "friends read public profile"
  on public.community_profiles
  for select
  to authenticated
  using (
    public.community_are_friends(auth.uid(), id)
    -- No email/phone/tokens live in this table by design.
  );

-- ================= friend requests + friendships policies =================

drop policy if exists "parties read requests" on public.friend_requests;
create policy "parties read requests"
  on public.friend_requests
  for select
  to authenticated
  using (auth.uid() = from_id or auth.uid() = to_id);

drop policy if exists "users send requests" on public.friend_requests;
create policy "users send requests"
  on public.friend_requests
  for insert
  to authenticated
  with check (auth.uid() = from_id and from_id <> to_id);

drop policy if exists "parties update requests" on public.friend_requests;
create policy "parties update requests"
  on public.friend_requests
  for update
  to authenticated
  using (auth.uid() = from_id or auth.uid() = to_id)
  with check (auth.uid() = from_id or auth.uid() = to_id);

drop policy if exists "members read friendships" on public.friendships;
create policy "members read friendships"
  on public.friendships
  for select
  to authenticated
  using (auth.uid() = user_low or auth.uid() = user_high);

-- Friendships are created by a secure function when a request is
-- accepted (never by direct client insert).
create or replace function public.accept_friend_request(request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  select * into r from public.friend_requests where id = request_id;
  if not found then
    raise exception 'request not found';
  end if;
  if r.status <> 'pending' then
    raise exception 'request already handled';
  end if;
  if auth.uid() <> r.to_id then
    raise exception 'not authorized';
  end if;
  update public.friend_requests
    set status = 'accepted'
    where id = request_id;
  insert into public.friendships (user_low, user_high)
    values (least(r.from_id, r.to_id), greatest(r.from_id, r.to_id))
    on conflict do nothing;
end;
$$;

-- ---------- rooms + presence ----------

create table if not exists public.study_rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 48),
  subject text,
  owner_id uuid not null references auth.users (id) on delete cascade,
  active boolean not null default true,
  focus_goal_min integer check (focus_goal_min is null or focus_goal_min > 0),
  created_at timestamptz not null default now()
);

create index if not exists study_rooms_active_idx
  on public.study_rooms (active, created_at desc);

create table if not exists public.room_invites (
  room_id uuid not null references public.study_rooms (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  primary key (room_id, user_id)
);

create table if not exists public.room_presence (
  room_id uuid not null references public.study_rooms (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  display_name text not null,
  last_beat_at timestamptz not null default now(),
  studying boolean not null default false,
  subject text,
  primary key (room_id, user_id)
);

create index if not exists room_presence_beat_idx
  on public.room_presence (room_id, last_beat_at desc);

alter table public.study_rooms enable row level security;
alter table public.room_invites enable row level security;
alter table public.room_presence enable row level security;

drop policy if exists "owner creates rooms" on public.study_rooms;
create policy "owner creates rooms"
  on public.study_rooms
  for insert
  to authenticated
  with check (auth.uid() = owner_id);

drop policy if exists "invited read rooms" on public.study_rooms;
create policy "invited read rooms"
  on public.study_rooms
  for select
  to authenticated
  using (
    auth.uid() = owner_id
    or exists (
      select 1 from public.room_invites i
      where i.room_id = id and i.user_id = auth.uid()
    )
    or exists (
      select 1 from public.room_presence p
      where p.room_id = id and p.user_id = auth.uid()
    )
  );

drop policy if exists "owner ends rooms" on public.study_rooms;
create policy "owner ends rooms"
  on public.study_rooms
  for update
  to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists "presence read by room viewers" on public.room_presence;
create policy "presence read by room viewers"
  on public.room_presence
  for select
  to authenticated
  using (
    exists (
      select 1 from public.study_rooms r
      where r.id = room_id
        and (
          r.owner_id = auth.uid()
          or exists (
            select 1 from public.room_invites i
            where i.room_id = r.id and i.user_id = auth.uid()
          )
        )
    )
  );

drop policy if exists "own presence write" on public.room_presence;
create policy "own presence write"
  on public.room_presence
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Stale presence (>120s without a heartbeat) is ignored by clients and
-- swept here; run via pg_cron or a scheduled edge function.
create or replace function public.sweep_stale_presence()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.room_presence
  where last_beat_at < now() - interval '120 seconds';
$$;

-- ---------- challenges ----------

create table if not exists public.challenges (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 64),
  goal_kind text not null check (goal_kind in ('hours', 'days')),
  target_minutes integer not null default 0 check (target_minutes >= 0),
  target_days integer not null default 0 check (target_days >= 0),
  start_day date not null,
  end_day date not null,
  owner_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  check (end_day > start_day)
);

create index if not exists challenges_owner_idx
  on public.challenges (owner_id, end_day desc);

create table if not exists public.challenge_participants (
  challenge_id uuid not null references public.challenges (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'invited'
    check (status in ('invited', 'accepted', 'declined', 'left')),
  primary key (challenge_id, user_id)
);

create index if not exists challenge_participants_user_idx
  on public.challenge_participants (user_id, status);

alter table public.challenges enable row level security;
alter table public.challenge_participants enable row level security;

drop policy if exists "participants read challenges" on public.challenges;
create policy "participants read challenges"
  on public.challenges
  for select
  to authenticated
  using (
    auth.uid() = owner_id
    or exists (
      select 1 from public.challenge_participants p
      where p.challenge_id = id and p.user_id = auth.uid()
    )
  );

drop policy if exists "users create challenges" on public.challenges;
create policy "users create challenges"
  on public.challenges
  for insert
  to authenticated
  with check (auth.uid() = owner_id);

drop policy if exists "owner deletes open challenges" on public.challenges;
create policy "owner deletes open challenges"
  on public.challenges
  for delete
  to authenticated
  using (auth.uid() = owner_id and end_day >= current_date);

drop policy if exists "participants manage own row" on public.challenge_participants;
create policy "participants manage own row"
  on public.challenge_participants
  for all
  to authenticated
  using (
    auth.uid() = user_id
    or exists (
      select 1 from public.challenges c
      where c.id = challenge_id and c.owner_id = auth.uid()
    )
  )
  with check (
    auth.uid() = user_id
    or exists (
      select 1 from public.challenges c
      where c.id = challenge_id and c.owner_id = auth.uid()
    )
  );

-- ---------- moderation ----------

create table if not exists public.moderation_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users (id) on delete cascade,
  reported_id uuid not null references auth.users (id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now(),
  check (reporter_id <> reported_id)
);

alter table public.moderation_reports enable row level security;

drop policy if exists "users file reports" on public.moderation_reports;
create policy "users file reports"
  on public.moderation_reports
  for insert
  to authenticated
  with check (auth.uid() = reporter_id);
