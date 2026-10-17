-- StudyUp social backend hardening fix (safe to run on live data).
--
-- Run AFTER 20261102_social_backend.sql (re-running that file first is
-- also safe and recommended). This file fixes two real issues found
-- during verification against a live project:
--
-- 1. "function digest(text, unknown) does not exist" on
--    invitation_preview / accept_invitation. Supabase installs pgcrypto
--    into the extensions schema, but the social RPCs locked
--    search_path = public, hiding digest() at execution time
--    (CREATE succeeded because plpgsql bodies validate on first call,
--    not at creation). Fixed by appending the extensions schema.
--    Unknown schemas in search_path are silently skipped, so this is
--    safe on self-hosted layouts where pgcrypto lives in public.
--
-- 2. Least-privilege EXECUTE re-asserted idempotently: revoke from
--    PUBLIC and anon, then grant exactly to authenticated (or anon +
--    authenticated for the deliberately public preview). Revoking a
--    non-held grant is only a notice. Also closes anonymous probing of
--    the friendship helper.
--
-- 3. community_are_friends now returns false for anonymous callers
--    instead of evaluating pair membership for them.
--
-- No tables, columns, policies, or data are touched. Repeatable.

create extension if not exists pgcrypto;

-- ---------- 1. digest() visibility ----------
alter function public.invitation_preview(text)
  set search_path = public, extensions;
alter function public.accept_invitation(text)
  set search_path = public, extensions;

-- ---------- 2. no anonymous friendship oracle ----------
create or replace function public.community_are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from public.friendships f
    where (f.user_low = least(a, b) and f.user_high = greatest(a, b))
  );
$$;

-- ---------- 3. least-privilege EXECUTE (converges regardless of history) ----------
revoke all on function public.create_invitation(text, timestamptz) from public, anon;
grant execute on function public.create_invitation(text, timestamptz) to authenticated;

revoke all on function public.accept_invitation(text) from public, anon;
grant execute on function public.accept_invitation(text) to authenticated;

revoke all on function public.invitation_preview(text) from public, anon;
grant execute on function public.invitation_preview(text) to anon, authenticated;

revoke all on function public.my_friends() from public, anon;
grant execute on function public.my_friends() to authenticated;

revoke all on function public.search_users(text) from public, anon;
grant execute on function public.search_users(text) to authenticated;

revoke all on function public.leaderboard_scope(text, timestamptz, timestamptz) from public, anon;
grant execute on function public.leaderboard_scope(text, timestamptz, timestamptz) to authenticated;

revoke all on function public.daily_rows(uuid, date, date) from public, anon;
grant execute on function public.daily_rows(uuid, date, date) to authenticated;

revoke all on function public.session_total_seconds(jsonb) from public, anon;
grant execute on function public.session_total_seconds(jsonb) to authenticated;

revoke all on function public.handle_new_user() from public, anon;
grant execute on function public.handle_new_user() to authenticated;

revoke all on function public.validate_request_transition() from public, anon;
grant execute on function public.validate_request_transition() to authenticated;

revoke all on function public.materialize_friendship() from public, anon;
grant execute on function public.materialize_friendship() to authenticated;

revoke all on function public.validate_session_days() from public, anon;
grant execute on function public.validate_session_days() to authenticated;

revoke all on function public.sweep_stale_presence() from public, anon;
grant execute on function public.sweep_stale_presence() to authenticated;
