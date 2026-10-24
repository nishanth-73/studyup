-- StudyUp social backend v2 (Supabase/Postgres).
--
-- Applies AFTER 20261015_community.sql (which created community_profiles,
-- friend_requests, friendships, rooms, challenges). This file only ADDS:
-- profile auto-creation, secure invitations, synced study sessions with
-- validated per-day splits, leaderboard RPCs, and hardened RLS. It never
-- drops user data; every statement is re-runnable (IF NOT EXISTS / policy
-- drops / CREATE OR REPLACE).
--
-- Tables owned by authenticated users only; cross-user reads go through
-- explicit friendship/opt-in policies or SECURITY DEFINER RPCs with a
-- locked search_path. The service-role key is never needed client-side.
create extension if not exists pgcrypto;

-- ================= prerequisites =================
-- This file extends 20261015_community.sql: it reads (never recreates)
-- community_profiles, friend_requests, and friendships. Fail fast with a
-- clear message if that file has not been applied yet, instead of a
-- cryptic "relation does not exist" halfway through.
do $$
begin
  if to_regclass('public.community_profiles') is null
     or to_regclass('public.friend_requests') is null
     or to_regclass('public.friendships') is null then
    raise exception
      'StudyUp setup out of order: run supabase/migrations/20261015_community.sql first, then re-run this file.';
  end if;
end $$;

-- ================= profile auto-creation =================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.community_profiles (id, display_name, avatar_id, blob_variant)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'Student'),
    coalesce(nullif(new.raw_user_meta_data ->> 'avatar_id', ''), 'robo-default'),
    coalesce((new.raw_user_meta_data ->> 'blob_variant')::int, 0)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ================= invitations =================
-- Single/multi-use invite links. Only the SHA-256 hash is stored; the raw
-- token lives in the shared URL and is never persisted server-side.

create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  max_uses integer not null default 1 check (max_uses between 1 and 50),
  uses integer not null default 0 check (uses >= 0),
  status text not null default 'active'
    check (status in ('active', 'accepted', 'expired', 'revoked')),
  check (expires_at > created_at)
);

create index if not exists invitations_creator_idx
  on public.invitations (created_by, created_at desc);

alter table public.invitations enable row level security;

-- Nobody lists invitations: resolution happens only through the
-- SECURITY DEFINER preview/accept RPCs (prevents token enumeration).
drop policy if exists "creator manages invitations" on public.invitations;
create policy "creator manages invitations"
  on public.invitations
  for all
  to authenticated
  using (auth.uid() = created_by)
  with check (auth.uid() = created_by);

-- Mint an invitation (server stamps the creator; the client supplies only
-- the hash of its locally generated secret + an expiry <= 30 days).
create or replace function public.create_invitation(
  p_token_hash text,
  p_expires_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'bad token hash' using errcode = '22000';
  end if;
  if p_expires_at is null
     or p_expires_at <= now()
     or p_expires_at > now() + interval '30 days' then
    raise exception 'bad expiry' using errcode = '22000';
  end if;
  insert into public.invitations (token_hash, created_by, expires_at)
  values (p_token_hash, auth.uid(), p_expires_at)
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.create_invitation(text, timestamptz) from public;
grant execute on function public.create_invitation(text, timestamptz) to authenticated;

-- Public preview: who invited me? Callable WITHOUT login (the token is
-- the secret) and returns display fields only — never emails or totals.
create or replace function public.invitation_preview(p_token text)
returns table (display_name text, avatar_id text, valid boolean, reason text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text;
  r record;
begin
  if p_token is null or length(p_token) < 16 then
    return query select ''::text, ''::text, false, 'invalid'::text;
    return;
  end if;
  v_hash := encode(digest(p_token, 'sha256'), 'hex');
  select i.*, p.display_name, p.avatar_id into r
  from public.invitations i
  join public.community_profiles p on p.id = i.created_by
  where i.token_hash = v_hash;
  if not found then
    return query select ''::text, ''::text, false, 'invalid'::text;
    return;
  end if;
  if r.status = 'revoked' then
    return query select r.display_name, r.avatar_id, false, 'revoked'::text;
    return;
  end if;
  if r.status = 'accepted' and r.uses >= r.max_uses then
    return query select r.display_name, r.avatar_id, false, 'accepted'::text;
    return;
  end if;
  if r.expires_at <= now() then
    update public.invitations set status = 'expired' where id = r.id;
    return query select r.display_name, r.avatar_id, false, 'expired'::text;
    return;
  end if;
  return query select r.display_name, r.avatar_id, true, 'ok'::text;
end;
$$;

grant execute on function public.invitation_preview(text) to anon, authenticated;
-- NOTE: preview is intentionally public (the token itself is the secret)
-- but returns display fields only.

-- Accept an invitation: validates everything server-side in one
-- transaction (no trust in client-supplied sender ids). Single-use by
-- default; raises on self-invite, duplicates, expiry, or revocation.
create or replace function public.accept_invitation(p_token text)
returns table (friend_id uuid, display_name text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text;
  v_inv record;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_token is null or length(p_token) < 16 then
    raise exception 'invalid token' using errcode = '22000';
  end if;
  v_hash := encode(digest(p_token, 'sha256'), 'hex');

  select * into v_inv
  from public.invitations
  where token_hash = v_hash
  for update;

  if not found then
    raise exception 'invalid token' using errcode = '22000';
  end if;
  if v_inv.status = 'revoked' then
    raise exception 'revoked' using errcode = '22000';
  end if;
  if v_inv.expires_at <= now() then
    update public.invitations set status = 'expired' where id = v_inv.id;
    raise exception 'expired' using errcode = '22000';
  end if;
  if v_inv.status <> 'active' or v_inv.uses >= v_inv.max_uses then
    raise exception 'already accepted' using errcode = '22000';
  end if;
  if v_inv.created_by = auth.uid() then
    raise exception 'self invite' using errcode = '22000';
  end if;
  if public.community_are_friends(auth.uid(), v_inv.created_by) then
    raise exception 'already friends' using errcode = '22000';
  end if;
  if exists (
    select 1 from public.friend_requests r
    where r.status = 'pending'
      and ((r.from_id = auth.uid() and r.to_id = v_inv.created_by)
        or (r.from_id = v_inv.created_by and r.to_id = auth.uid()))
  ) then
    raise exception 'request pending' using errcode = '22000';
  end if;

  insert into public.friendships (user_low, user_high)
  values (
    least(auth.uid(), v_inv.created_by),
    greatest(auth.uid(), v_inv.created_by)
  )
  on conflict do nothing;

  update public.invitations
  set uses = uses + 1,
      status = case when uses + 1 >= max_uses then 'accepted'::text else 'active'::text end
  where id = v_inv.id;

  -- Retire any stray open requests between the pair (accepted wins).
  update public.friend_requests
  set status = 'cancelled'
  where status = 'pending'
    and ((from_id = auth.uid() and to_id = v_inv.created_by)
      or (from_id = v_inv.created_by and to_id = auth.uid()));

  return query
    select p.id, p.display_name
    from public.community_profiles p
    where p.id = v_inv.created_by;
end;
$$;

revoke all on function public.accept_invitation(text) from public;
grant execute on function public.accept_invitation(text) to authenticated;

-- ================= friend request transitions =================
-- Policies allow both parties to touch a request; this trigger enforces
-- WHO may move it WHERE: recipients accept/decline, senders cancel only.

create or replace function public.validate_request_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status <> 'pending' then
    raise exception 'request already handled' using errcode = '22000';
  end if;
  if new.status = 'accepted' or new.status = 'declined' then
    if auth.uid() <> old.to_id then
      raise exception 'not recipient' using errcode = '28000';
    end if;
  elsif new.status = 'cancelled' then
    if auth.uid() <> old.from_id then
      raise exception 'not sender' using errcode = '28000';
    end if;
  else
    raise exception 'bad status' using errcode = '22000';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_request_transition on public.friend_requests;
create trigger validate_request_transition
  before update of status on public.friend_requests
  for each row execute function public.validate_request_transition();

-- On acceptance, materialize the friendship atomically (race-safe via
-- the friendships PK + ON CONFLICT).
create or replace function public.materialize_friendship()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'accepted' and old.status = 'pending' then
    insert into public.friendships (user_low, user_high)
    values (least(new.from_id, new.to_id), greatest(new.from_id, new.to_id))
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists materialize_friendship on public.friend_requests;
create trigger materialize_friendship
  after update of status on public.friend_requests
  for each row execute function public.materialize_friendship();

-- ================= synced study sessions =================
-- Raw session records owned exclusively by their author. The leaderboard
-- never reads these for friends — only validated per-day aggregates.

create table if not exists public.study_sessions (
  id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  subject_id text not null default 'general',
  subject_name text not null default 'Daily Study',
  check_in timestamptz not null,
  check_out timestamptz,
  paused_seconds integer not null default 0 check (paused_seconds >= 0),
  segments jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (check_out is null or check_out > check_in),
  check (jsonb_typeof(segments) = 'array')
);

create index if not exists study_sessions_user_idx
  on public.study_sessions (user_id, check_in desc);

alter table public.study_sessions enable row level security;

drop policy if exists "owner manages sessions" on public.study_sessions;
create policy "owner manages sessions"
  on public.study_sessions
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ================= validated per-day splits =================
-- One row per (session, local calendar day) computed CLIENT-side (only
-- the device knows its timezone). The trigger verifies every row:
-- non-negative, day near the session, and per-session sums never
-- EXCEEDING the segment total — so clients cannot invent hours.
-- (Capped, not exact: multi-row splits sync row-by-row, and any
-- under-count only lowers the author's own totals.)

create or replace function public.session_total_seconds(segs jsonb)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
  el jsonb;
  total integer := 0;
  s timestamptz;
  e timestamptz;
begin
  for el in select * from jsonb_array_elements(coalesce(segs, '[]'::jsonb)) loop
    begin
      s := (el ->> 's')::timestamptz;
      e := (el ->> 'e')::timestamptz;
    exception when others then
      raise exception 'bad segment' using errcode = '22000';
    end;
    if e <= s then
      raise exception 'bad segment' using errcode = '22000';
    end if;
    if extract(epoch from (e - s)) > 86400 then
      raise exception 'segment too long' using errcode = '22000';
    end if;
    total := total + floor(extract(epoch from (e - s)))::int;
  end loop;
  return total;
end;
$$;

create table if not exists public.session_days (
  session_id text not null references public.study_sessions (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null check (day between date '2000-01-01' and (current_date + 1)),
  -- Instant the author's LOCAL day began (device computed). Lets the
  -- leaderboard count active days against exact instant ranges without
  -- the server guessing timezones. Must sit within a day of [day].
  day_start_utc timestamptz not null,
  seconds integer not null check (seconds >= 0 and seconds <= 86400),
  primary key (session_id, day)
);

create index if not exists session_days_user_day_idx
  on public.session_days (user_id, day);
create index if not exists session_days_day_idx
  on public.session_days (day);

alter table public.session_days enable row level security;

-- Owner: full access. Friends: read day aggregates (needed for shared
-- leaderboards/streaks — never raw session details). Opted-in strangers:
-- read for the public/community board.
drop policy if exists "owner manages session days" on public.session_days;
create policy "owner manages session days"
  on public.session_days
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "friends read day aggregates" on public.session_days;
create policy "friends read day aggregates"
  on public.session_days
  for select
  to authenticated
  using (public.community_are_friends(auth.uid(), user_id));

drop policy if exists "opted-in public aggregates" on public.session_days;
create policy "opted-in public aggregates"
  on public.session_days
  for select
  to authenticated
  using (
    exists (
      select 1 from public.community_profiles p
      where p.id = user_id and p.leaderboard_opt_in
    )
  );

create or replace function public.validate_session_days()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session record;
  v_sum integer;
  v_total integer;
begin
  select * into v_session
  from public.study_sessions
  where id = new.session_id;
  if not found then
    raise exception 'unknown session' using errcode = '22000';
  end if;
  if v_session.user_id <> new.user_id then
    raise exception 'user mismatch' using errcode = '22000';
  end if;
  if abs(extract(epoch from (new.day_start_utc - new.day::timestamptz)) / 86400) > 1 then
    raise exception 'day start mismatch' using errcode = '22000';
  end if;
  if new.day < (v_session.check_in - interval '1 day')::date
     or (v_session.check_out is not null
         and new.day > (v_session.check_out + interval '1 day')::date) then
    raise exception 'day out of range' using errcode = '22000';
  end if;
  select coalesce(sum(seconds), 0) into v_sum
  from public.session_days
  where session_id = new.session_id
    and (day, session_id) <> (new.day, new.session_id);
  v_total := public.session_total_seconds(v_session.segments);
  -- Cap, not exact equality: rows sync one by one and an exact check
  -- would reject legitimate partial states.
  if v_sum + new.seconds > v_total then
    raise exception 'split exceeds session total: % > %', v_sum + new.seconds, v_total
      using errcode = '22000';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_session_days on public.session_days;
create trigger validate_session_days
  before insert or update on public.session_days
  for each row execute function public.validate_session_days();

-- ================= leaderboard RPCs =================
-- Server-computed from validated session_days only. Clients can never
-- set arbitrary totals, streaks, or levels; level/streak math stays
-- client-side with the documented formulas for display.

-- Accepted friends of the caller (id + public fields only).
create or replace function public.my_friends()
returns table (
  user_id uuid,
  display_name text,
  avatar_id text,
  blob_variant integer,
  leaderboard_opt_in boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.display_name, p.avatar_id, p.blob_variant, p.leaderboard_opt_in
  from public.community_profiles p
  where public.community_are_friends(auth.uid(), p.id)
  order by p.display_name;
$$;

revoke all on function public.my_friends() from public;
grant execute on function public.my_friends() to authenticated;

-- Display-name search across opted-in users (invite new friends).
-- Returns public fields only, capped at 20 rows.
create or replace function public.search_users(p_query text)
returns table (user_id uuid, display_name text, avatar_id text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.display_name, p.avatar_id
  from public.community_profiles p
  where p.leaderboard_opt_in
    and p.id <> auth.uid()
    and p.display_name ilike '%' || left(coalesce(p_query, ''), 48) || '%'
  order by p.display_name
  limit 20;
$$;

revoke all on function public.search_users(text) from public;
grant execute on function public.search_users(text) to authenticated;

-- Weekly board. scope 'friends': accepted friends (opted in). scope
-- 'everyone': all opted-in users (public board, capped at 100).
-- Bounds are caller-supplied instants (the device computes its local
-- Monday–Sunday window); the server only sums validated overlaps.
create or replace function public.leaderboard_scope(
  p_scope text,
  p_start timestamptz,
  p_end timestamptz
)
returns table (
  user_id uuid,
  display_name text,
  avatar_id text,
  blob_variant integer,
  week_seconds bigint,
  active_days bigint,
  total_seconds bigint,
  streak_days integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_scope <> 'friends' and p_scope <> 'everyone' then
    raise exception 'bad scope' using errcode = '22000';
  end if;
  if p_end <= p_start or p_end - p_start > interval '8 days' then
    raise exception 'bad range' using errcode = '22000';
  end if;
  if p_start < timestamptz '2000-01-01' or p_end > now() + interval '8 days' then
    raise exception 'range out of bounds' using errcode = '22000';
  end if;
  return query
  with eligible as (
    select p.id
    from public.community_profiles p
    where p.leaderboard_opt_in
      and (
        p_scope = 'everyone'
        or public.community_are_friends(auth.uid(), p.id)
        or p.id = auth.uid()
      )
  ),
  -- Exact overlap seconds from validated segments. This definer function
  -- may read segments rows, but only SUMS leave the database.
  week as (
    select s.user_id,
           coalesce(sum(
             case
               when (el ->> 'e')::timestamptz > p_start
                and (el ->> 's')::timestamptz < p_end
               then extract(epoch from (
                 least((el ->> 'e')::timestamptz, p_end) -
                 greatest((el ->> 's')::timestamptz, p_start)
               ))
               else 0
             end
           ), 0)::bigint as week_seconds
    from public.study_sessions s
    cross join jsonb_array_elements(
      case when jsonb_typeof(s.segments) = 'array' then s.segments else '[]'::jsonb end
    ) el
    where s.user_id in (select id from eligible)
    group by s.user_id
  ),
  wdays as (
    select d.user_id, count(*)::bigint as active_days
    from public.session_days d
    where d.seconds > 0
      and d.day_start_utc < p_end
      and d.day_start_utc + interval '24 hours' > p_start
      and d.user_id in (select id from eligible)
    group by d.user_id
  ),
  totals as (
    select d.user_id, coalesce(sum(d.seconds), 0)::bigint as total_seconds
    from public.session_days d
    where d.user_id in (select id from eligible)
    group by d.user_id
  ),
  -- Current streak per StudyUp definition: consecutive studied days
  -- counting back from today (quiet today allowed when yesterday was
  -- studied). Computed here so every client shows the same value.
  streak as (
    select days.user_id, count(*)::int as streak_days
    from (
      select d.user_id, d.day,
             row_number() over (
               partition by d.user_id order by d.day desc
             ) as rn,
             max(d.day) over (partition by d.user_id) as anchor
      from public.session_days d
      where d.seconds > 0
        and d.day <= current_date
        and d.user_id in (select id from eligible)
    ) days
    where anchor >= current_date - 1
      and day = anchor - (rn - 1)::integer
    group by days.user_id
  )
  select p.id, p.display_name, p.avatar_id, p.blob_variant,
         coalesce(w.week_seconds, 0), coalesce(wd.active_days, 0),
         coalesce(t.total_seconds, 0), coalesce(s.streak_days, 0)
  from public.community_profiles p
  left join week w on w.user_id = p.id
  left join wdays wd on wd.user_id = p.id
  left join totals t on t.user_id = p.id
  left join streak s on s.user_id = p.id
  where p.id in (select id from eligible)
    and (p.id = auth.uid() or coalesce(w.week_seconds, 0) > 0 or p_scope = 'everyone')
  order by coalesce(w.week_seconds, 0) desc, p.display_name
  limit 100;
end;
$$;

revoke all on function public.leaderboard_scope(text, timestamptz, timestamptz) from public;
grant execute on function public.leaderboard_scope(text, timestamptz, timestamptz) to authenticated;

-- Daily rows for streak math (caller + friends + opt-in users).
create or replace function public.daily_rows(
  p_user_id uuid,
  p_from date,
  p_to date
)
returns table (day date, seconds integer)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_to < p_from or p_to - p_from > 730 then
    raise exception 'bad range' using errcode = '22000';
  end if;
  if p_user_id <> auth.uid()
     and not public.community_are_friends(auth.uid(), p_user_id) then
    -- Strangers: only when opted in.
    if not exists (
      select 1 from public.community_profiles p
      where p.id = p_user_id and p.leaderboard_opt_in
    ) then
      raise exception 'not permitted' using errcode = '28000';
    end if;
  end if;
  return query
  select d.day, d.seconds
  from public.session_days d
  where d.user_id = p_user_id
    and d.day between p_from and p_to
  order by d.day;
end;
$$;

revoke all on function public.daily_rows(uuid, date, date) from public;
grant execute on function public.daily_rows(uuid, date, date) to authenticated;

-- ================= realtime =================
-- Friend requests + invitations stream to the UI (RLS-filtered per
-- subscriber; session tables intentionally NOT broadcast).

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'friend_requests'
  ) then
    alter publication supabase_realtime add table public.friend_requests;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'invitations'
  ) then
    alter publication supabase_realtime add table public.invitations;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'community_profiles'
  ) then
    alter publication supabase_realtime add table public.community_profiles;
  end if;
end $$;
