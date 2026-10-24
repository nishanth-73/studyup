-- ============================================================================
-- StudyUp Community & Social Baseline Migration
-- ============================================================================
--
-- Implements:
-- 1. Tables: profiles, sessions, invites, friendships, activity_pings, app_waitlist
-- 2. Row Level Security on all tables
-- 3. Rate limiting for invite creation (max 20 per 24h)
-- 4. 5 core SECURITY DEFINER functions:
--    - get_invite_preview(p_token text)
--    - accept_invite(p_token text)
--    - get_community_home(p_week_start date)
--    - get_week_detail(p_user_id uuid, p_week_start date)
--    - complete_session(duration_minutes int)
-- 5. Helper streak and weekly card calculation functions
-- 6. Explicit grants and search_path hardening
-- 7. Realtime publication for activity_pings

begin;

-- ============================================================================
-- 0. CLEANUP OF OBSOLETE LEGACY COMMUNITY OBJECTS (IF PRESENT)
-- ============================================================================
-- Drops obsolete objects from older schema iterations so the new baseline
-- installs cleanly on any database state. Never touches auth.* or storage.*.
drop table if exists public.challenge_participants cascade;
drop table if exists public.challenges cascade;
drop table if exists public.room_presence cascade;
drop table if exists public.room_invites cascade;
drop table if exists public.study_rooms cascade;
drop table if exists public.community_progress_events cascade;
drop table if exists public.moderation_reports cascade;
drop table if exists public.blocks cascade;
drop table if exists public.invitation_acceptances cascade;
drop table if exists public.invitations cascade;
drop table if exists public.friend_requests cascade;
drop table if exists public.community_profiles cascade;
drop table if exists public.session_days cascade;
drop table if exists public.study_sessions cascade;

-- If legacy friendships table exists with old columns (e.g. user_low/user_high without user_a), drop it
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'friendships'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'friendships' and column_name = 'user_a'
  ) then
    drop table public.friendships cascade;
  end if;
end;
$$;

-- If legacy sessions table exists without duration_minutes, drop it
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'sessions'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'sessions' and column_name = 'duration_minutes'
  ) then
    drop table public.sessions cascade;
  end if;
end;
$$;

-- If legacy invites table exists without token, drop it
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'invites'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'invites' and column_name = 'token'
  ) then
    drop table public.invites cascade;
  end if;
end;
$$;

-- ============================================================================
-- 1. TABLES
-- ============================================================================

-- PROFILES
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  avatar_url text,
  weekly_goal_minutes int not null default 600 check (weekly_goal_minutes > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- SESSIONS
create table if not exists public.sessions (
  id text primary key default gen_random_uuid()::text,
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  duration_minutes int not null check (duration_minutes >= 0),
  completed boolean not null default true
);

create index if not exists idx_sessions_user_week
  on public.sessions (user_id, started_at)
  where completed = true;

-- INVITES
create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  token text unique not null,
  inviter_id uuid not null references auth.users(id) on delete cascade,
  used_by uuid references auth.users(id) on delete set null,
  used_at timestamptz,
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now()
);

create index if not exists idx_invites_token on public.invites (token);
create index if not exists idx_invites_inviter_created on public.invites (inviter_id, created_at);

-- FRIENDSHIPS (Bidirectional storage: both (A,B) and (B,A))
create table if not exists public.friendships (
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  constraint chk_no_self_friendship check (user_a <> user_b)
);

create index if not exists idx_friendships_user_a on public.friendships (user_a);

-- ACTIVITY PINGS (For Realtime updates without reading raw sessions)
create table if not exists public.activity_pings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists idx_activity_pings_user on public.activity_pings (user_id, created_at desc);

-- APP WAITLIST (For Android APK / Waitlist notifications)
create table if not exists public.app_waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_app_waitlist_email on public.app_waitlist (email);

-- ============================================================================
-- 2. ROW LEVEL SECURITY (RLS)
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.sessions enable row level security;
alter table public.invites enable row level security;
alter table public.friendships enable row level security;
alter table public.activity_pings enable row level security;
alter table public.app_waitlist enable row level security;

-- PROFILES: Users can select/insert/update own row. No direct friend reads (done via functions).
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (id = auth.uid());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- SESSIONS: User can select/insert/update/delete ONLY own sessions. Friends NEVER read raw rows.
drop policy if exists "sessions_select_own" on public.sessions;
create policy "sessions_select_own" on public.sessions
  for select using (user_id = auth.uid());

drop policy if exists "sessions_insert_own" on public.sessions;
create policy "sessions_insert_own" on public.sessions
  for insert with check (user_id = auth.uid());

drop policy if exists "sessions_update_own" on public.sessions;
create policy "sessions_update_own" on public.sessions
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "sessions_delete_own" on public.sessions;
create policy "sessions_delete_own" on public.sessions
  for delete using (user_id = auth.uid());

-- INVITES: Users can insert and select own created invites. Accept/preview goes through functions.
drop policy if exists "invites_insert_own" on public.invites;
create policy "invites_insert_own" on public.invites
  for insert with check (inviter_id = auth.uid());

drop policy if exists "invites_select_own" on public.invites;
create policy "invites_select_own" on public.invites
  for select using (inviter_id = auth.uid());

-- FRIENDSHIPS: Users can select friendships where user_a = auth.uid(). No direct client inserts.
drop policy if exists "friendships_select_own" on public.friendships;
create policy "friendships_select_own" on public.friendships
  for select using (user_a = auth.uid());

-- ACTIVITY PINGS: Insert own ping; select own or friend pings.
drop policy if exists "pings_insert_own" on public.activity_pings;
create policy "pings_insert_own" on public.activity_pings
  for insert with check (user_id = auth.uid());

drop policy if exists "pings_select_friends" on public.activity_pings;
create policy "pings_select_friends" on public.activity_pings
  for select using (
    user_id = auth.uid()
    or exists (
      select 1 from public.friendships f
      where f.user_a = auth.uid() and f.user_b = public.activity_pings.user_id
    )
  );

-- APP WAITLIST: Public insert
drop policy if exists "waitlist_insert" on public.app_waitlist;
create policy "waitlist_insert" on public.app_waitlist
  for insert with check (true);

-- ============================================================================
-- 3. TRIGGERS
-- ============================================================================

-- Rate limiting for invite creation: max 20 invites per user per 24 hours
create or replace function public.check_invite_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  select count(*) into v_count
  from public.invites
  where inviter_id = new.inviter_id
    and created_at >= (now() - interval '24 hours');

  if v_count >= 20 then
    raise exception 'Daily invitation limit reached (maximum 20 invites per 24 hours).';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_check_invite_rate_limit on public.invites;
create trigger trg_check_invite_rate_limit
before insert on public.invites
for each row
execute function public.check_invite_rate_limit();

-- Auto-create profile on auth.users creation
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, name, avatar_url, weekly_goal_minutes)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    new.raw_user_meta_data->>'avatar_url',
    600
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ============================================================================
-- 4. CALCULATION HELPER FUNCTIONS
-- ============================================================================

-- STREAK CALCULATION: consecutive calendar days with at least 1 completed session
create or replace function public.calculate_streak(p_user_id uuid, p_today date)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_streak int := 0;
  v_check_date date := p_today;
  v_has_today boolean;
begin
  select exists (
    select 1 from public.sessions
    where user_id = p_user_id
      and completed = true
      and started_at >= v_check_date
      and started_at < (v_check_date + interval '1 day')
  ) into v_has_today;

  if not v_has_today then
    v_check_date := p_today - 1;
  end if;

  while exists (
    select 1 from public.sessions
    where user_id = p_user_id
      and completed = true
      and started_at >= v_check_date
      and started_at < (v_check_date + interval '1 day')
  ) loop
    v_streak := v_streak + 1;
    v_check_date := v_check_date - 1;
  end loop;

  return v_streak;
end;
$$;

-- WEEKLY CARD CALCULATION
create or replace function public.get_weekly_card(p_user_id uuid, p_week_start date)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_start date := date_trunc('week', p_week_start::timestamp)::date;
  v_week_end date := v_week_start + 7;
  v_completed_sessions int;
  v_total_minutes int;
  v_goal_minutes int;
  v_percent int;
  v_streak int;
begin
  select
    coalesce(count(*), 0),
    coalesce(sum(duration_minutes), 0)
  into v_completed_sessions, v_total_minutes
  from public.sessions
  where user_id = p_user_id
    and completed = true
    and started_at >= v_week_start
    and started_at < v_week_end;

  select coalesce(weekly_goal_minutes, 600)
  into v_goal_minutes
  from public.profiles
  where id = p_user_id;

  if v_goal_minutes is null or v_goal_minutes <= 0 then
    v_goal_minutes := 600;
  end if;

  v_percent := round((v_total_minutes::numeric / v_goal_minutes) * 100)::int;
  v_streak := public.calculate_streak(p_user_id, (now() at time zone 'UTC')::date);

  return json_build_object(
    'week_start', v_week_start,
    'completed_sessions', v_completed_sessions,
    'total_minutes', v_total_minutes,
    'goal_minutes', v_goal_minutes,
    'percent', v_percent,
    'streak', v_streak
  );
end;
$$;

-- ============================================================================
-- 5. SPECIFIED CORE SQL FUNCTIONS
-- ============================================================================

-- 1. GET_INVITE_PREVIEW: callable by anon & authenticated
create or replace function public.get_invite_preview(p_token text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite record;
  v_inviter_name text;
  v_inviter_avatar text;
  v_percent int;
  v_week_card json;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return json_build_object('status', 'invalid');
  end if;

  select * into v_invite
  from public.invites
  where token = p_token;

  if not found then
    return json_build_object('status', 'invalid');
  end if;

  if v_invite.used_by is not null or v_invite.used_at is not null then
    return json_build_object('status', 'used');
  end if;

  if v_invite.expires_at < now() then
    return json_build_object('status', 'expired');
  end if;

  -- Get inviter profile
  select name, avatar_url
  into v_inviter_name, v_inviter_avatar
  from public.profiles
  where id = v_invite.inviter_id;

  -- Get current-week percent
  v_week_card := public.get_weekly_card(v_invite.inviter_id, (now() at time zone 'UTC')::date);
  v_percent := (v_week_card->>'percent')::int;

  return json_build_object(
    'status', 'valid',
    'inviter_name', coalesce(v_inviter_name, 'A friend'),
    'inviter_avatar', v_inviter_avatar,
    'current_week_percent', coalesce(v_percent, 0)
  );
end;
$$;

-- 2. ACCEPT_INVITE: race-safe, locks invite row
create or replace function public.accept_invite(p_token text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_invite record;
begin
  if v_uid is null then
    raise exception 'Authentication required to accept invitations';
  end if;

  if p_token is null or length(trim(p_token)) = 0 then
    return 'invalid';
  end if;

  -- Lock the row (select ... for update)
  select * into v_invite
  from public.invites
  where token = p_token
  for update;

  if not found then
    return 'invalid';
  end if;

  if v_invite.used_by is not null or v_invite.used_at is not null then
    return 'used';
  end if;

  if v_invite.expires_at < now() then
    return 'expired';
  end if;

  if v_invite.inviter_id = v_uid then
    return 'own';
  end if;

  if exists (
    select 1 from public.friendships
    where user_a = v_uid and user_b = v_invite.inviter_id
  ) then
    return 'already_friends';
  end if;

  -- Mark invite as used
  update public.invites
  set used_by = v_uid, used_at = now()
  where id = v_invite.id;

  -- Insert bidirectional friendship rows
  insert into public.friendships (user_a, user_b, created_at)
  values (v_uid, v_invite.inviter_id, now())
  on conflict do nothing;

  insert into public.friendships (user_a, user_b, created_at)
  values (v_invite.inviter_id, v_uid, now())
  on conflict do nothing;

  -- Notify via activity ping
  insert into public.activity_pings (user_id, created_at)
  values (v_uid, now()), (v_invite.inviter_id, now());

  return 'ok';
end;
$$;

-- 3. GET_COMMUNITY_HOME: returns { me: {weekly card, today's session card}, friends: [ {id, name, avatar, weekly card} ] }
create or replace function public.get_community_home(p_week_start date default null)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_week_start date;
  v_today date := (now() at time zone 'UTC')::date;
  v_me_profile record;
  v_me_weekly json;
  v_me_today json;
  v_today_sessions int;
  v_today_minutes int;
  v_friends json;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if p_week_start is null then
    v_week_start := date_trunc('week', now() at time zone 'UTC')::date;
  else
    v_week_start := date_trunc('week', p_week_start::timestamp)::date;
  end if;

  -- Ensure profile exists
  insert into public.profiles (id, name, weekly_goal_minutes)
  values (v_uid, 'You', 600)
  on conflict (id) do nothing;

  select * into v_me_profile
  from public.profiles
  where id = v_uid;

  v_me_weekly := public.get_weekly_card(v_uid, v_week_start);

  -- Today's sessions
  select
    coalesce(count(*), 0),
    coalesce(sum(duration_minutes), 0)
  into v_today_sessions, v_today_minutes
  from public.sessions
  where user_id = v_uid
    and completed = true
    and started_at >= v_today
    and started_at < (v_today + interval '1 day');

  v_me_today := json_build_object(
    'date', v_today,
    'completed_sessions', v_today_sessions,
    'total_minutes', v_today_minutes
  );

  -- Friends list from friendships table for auth.uid()
  select coalesce(
    json_agg(
      json_build_object(
        'id', f.user_b,
        'name', coalesce(p.name, 'Study Friend'),
        'avatar', p.avatar_url,
        'weekly_card', public.get_weekly_card(f.user_b, v_week_start)
      )
      order by coalesce(p.name, 'Study Friend') asc
    ),
    '[]'::json
  )
  into v_friends
  from public.friendships f
  left join public.profiles p on p.id = f.user_b
  where f.user_a = v_uid;

  return json_build_object(
    'me', json_build_object(
      'id', v_uid,
      'name', coalesce(v_me_profile.name, 'You'),
      'avatar', v_me_profile.avatar_url,
      'weekly_card', v_me_weekly,
      'today_card', v_me_today
    ),
    'friends', v_friends
  );
end;
$$;

-- 4. GET_WEEK_DETAIL: 7 days breakdown for me or friend
create or replace function public.get_week_detail(p_user_id uuid, p_week_start date)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_week_start date;
  v_target_profile record;
  v_weekly_card json;
  v_days json;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if p_user_id <> v_uid then
    if not exists (
      select 1 from public.friendships
      where user_a = v_uid and user_b = p_user_id
    ) then
      raise exception 'Access denied: not accepted friends';
    end if;
  end if;

  v_week_start := date_trunc('week', p_week_start::timestamp)::date;

  select * into v_target_profile
  from public.profiles
  where id = p_user_id;

  v_weekly_card := public.get_weekly_card(p_user_id, v_week_start);

  -- 7 days Monday to Sunday
  select json_agg(
    json_build_object(
      'date', (v_week_start + i * interval '1 day')::date,
      'minutes', coalesce(d.total_mins, 0),
      'sessions_completed', coalesce(d.sess_count, 0)
    )
    order by i asc
  )
  into v_days
  from generate_series(0, 6) as i
  left join lateral (
    select
      sum(s.duration_minutes) as total_mins,
      count(*) as sess_count
    from public.sessions s
    where s.user_id = p_user_id
      and s.completed = true
      and s.started_at >= (v_week_start + i * interval '1 day')
      and s.started_at < (v_week_start + (i + 1) * interval '1 day')
  ) d on true;

  return json_build_object(
    'user', json_build_object(
      'id', p_user_id,
      'name', case when p_user_id = v_uid then 'You' else coalesce(v_target_profile.name, 'Study Friend') end,
      'avatar', v_target_profile.avatar_url,
      'is_me', (p_user_id = v_uid)
    ),
    'weekly_card', v_weekly_card,
    'days', coalesce(v_days, '[]'::json)
  );
end;
$$;

-- 5. COMPLETE_SESSION: inserts session, writes ping, returns updated weekly card
create or replace function public.complete_session(duration_minutes int)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_week_start date;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if duration_minutes is null or duration_minutes < 1 then
    duration_minutes := 1;
  end if;

  insert into public.sessions (user_id, started_at, duration_minutes, completed)
  values (v_uid, now(), duration_minutes, true);

  insert into public.activity_pings (user_id, created_at)
  values (v_uid, now());

  v_week_start := date_trunc('week', now() at time zone 'UTC')::date;
  return public.get_weekly_card(v_uid, v_week_start);
end;
$$;

-- ============================================================================
-- 6. GRANTS AND EXECUTION PERMISSIONS
-- ============================================================================

revoke execute on all functions in schema public from public;

grant execute on function public.get_invite_preview(text) to anon, authenticated;
grant execute on function public.accept_invite(text) to authenticated;
grant execute on function public.get_community_home(date) to authenticated;
grant execute on function public.get_week_detail(uuid, date) to authenticated;
grant execute on function public.complete_session(int) to authenticated;

-- Allow authenticated users to insert to invites table
grant select, insert on public.invites to authenticated;
-- Allow authenticated users to read friendships
grant select on public.friendships to authenticated;
-- Allow authenticated users to read/insert pings
grant select, insert on public.activity_pings to authenticated;
-- Allow anon and authenticated to insert to app_waitlist
grant insert on public.app_waitlist to anon, authenticated;
-- Allow authenticated to manage own profiles & sessions
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.sessions to authenticated;

commit;

-- Realtime publication for activity_pings
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'activity_pings'
    ) then
      alter publication supabase_realtime add table public.activity_pings;
    end if;
  end if;
end;
$$;

