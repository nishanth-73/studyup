# Supabase verification steps (run manually after applying migrations)

These steps verify RLS and the invitation/leaderboard flows against a
real project. They need a service-role SQL session (Dashboard → SQL
editor runs as postgres, which bypasses RLS — so each check creates
least-privilege roles or uses `set role authenticated` + JWT claims).
Nothing here is auto-run by CI; record the results before release.

> Replace `USER_A` / `USER_B` with two real `auth.users.id` values from
> your project (sign up twice in the app first).

## 0. Apply migrations in order

```sql
-- In the Supabase SQL editor, run each file once, in order:
--   supabase/migrations/20261015_community.sql
--   supabase/migrations/20261102_social_backend.sql
--   supabase/migrations/20261104_hardening_fix.sql
--   supabase/migrations/20261112_friends_zero_progress.sql
--   supabase/migrations/20261113_community_progress_realtime.sql
--   supabase/migrations/20261114_community_weekly_dedup.sql
-- Apply each migration once and in order; do not skip prior migrations.
```

## 1. Profile auto-creation trigger

```sql
-- New sign-ups must get a community_profiles row automatically.
select id, display_name from community_profiles;
-- Expect: one row per auth.users row.
```

## 2. Invitation lifecycle (as USER_A client role)

```sql
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"USER_A"}', true);

-- Mint:
select create_invitation(encode(digest('test-raw-token-0001', 'sha256'), 'hex'), now() + interval '7 days');
-- Preview (logged out / anon is fine):
reset role;
select * from invitation_preview('test-raw-token-0001');
-- Expect: valid = true, inviter display name only.
```

## 3. Accept as USER_B; verify server-side guards

```sql
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"USER_B"}', true);
select * from accept_invitation('test-raw-token-0001');
-- Expect: one row (USER_A id + name); friendship row exists:
select * from friendships
 where (user_low, user_high) = (least('USER_A','USER_B'), greatest('USER_A','USER_B'));

-- Re-accept must fail (single-use):
select * from accept_invitation('test-raw-token-0001');
-- Expect: ERROR "already accepted".
reset role;
```

## 4. Self-invite, duplicates, expiry

```sql
-- USER_A accepting their own link → ERROR "self invite".
-- Re-mint after friendship exists → accept as USER_B → ERROR "already friends".
-- Expired invitation → preview returns valid=false, reason='expired'.
```

## 5. Friend-request transitions

```sql
-- As USER_A: insert into friend_requests (from_id=USER_A, to_id=<third user>).
-- As the RECIPIENT: update status to 'accepted' → friendships row appears
-- via trigger. As USER_A (sender) trying status='accepted' on own request
-- → ERROR "not recipient". Double-handling → ERROR "request already handled".
```

## 6. Cross-user isolation

```sql
-- As USER_B, try to write USER_A's profile or sessions:
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"USER_B"}', true);
update community_profiles set display_name = 'pwned' where id = 'USER_A';
-- Expect: 0 rows affected (policy allows only own id).
insert into study_sessions (id, user_id, check_in, segments)
  values ('x', 'USER_A', now(), '[]');
-- Expect: ERROR (WITH CHECK auth.uid() = user_id).
reset role;
```

## 7. Leaderboard RPC privacy

```sql
-- Opt USER_B out (leaderboard_opt_in = false as USER_B), then as USER_A:
select * from leaderboard_scope('friends', date_trunc('week', now()), date_trunc('week', now()) + interval '7 days');
-- Expect: USER_B remains listed but all progress aggregates are zero;
-- opted-out progress is not returned.
-- scope='everyone' as USER_A: ERROR "bad scope"; only accepted friends
-- can read the Community board.
-- scope='bogus' → ERROR "bad scope".
```

## 8. Historical current-week progress and boundary handling

```sql
-- As USER_A, insert one session with overlapping intervals in the current
-- Monday-to-Monday window and one interval in the prior week. Before
-- USER_A and USER_B become friends, those rows remain private.
-- After USER_B accepts USER_A's invitation, call the friends RPC as USER_B
-- with p_start = the viewer's local Monday midnight converted to UTC and
-- p_end = the following Monday midnight converted to UTC.
-- Expect USER_A's week_seconds to include the union of eligible current-
-- week intervals only: overlaps count once and the prior-week interval is
-- excluded. Repeating the call returns the same total. Only aggregate and
-- profile fields are returned, never raw segments.
```

## 9. Session-day validation

```sql
-- Insert a session as USER_A, then session_days rows whose seconds do
-- NOT sum to the segment total → ERROR "split mismatch".
-- Rows for another user_id → ERROR "user mismatch".

-- With USER_A opted out, USER_B cannot select USER_A's session_days and
-- daily_rows(USER_A, ...) fails with "not permitted", even if accepted.
-- After USER_A opts in and USER_A/USER_B are accepted friends, the daily
-- aggregates are available to USER_B. An unrelated signed-in user cannot
-- select USER_A's session_days or call daily_rows for USER_A, even when
-- USER_A opted in. Raw study_sessions remain owner-only.
```

## 10. Realtime publication and event visibility

```sql
select tablename from pg_publication_tables where pubname = 'supabase_realtime';
-- Expect: friend_requests, invitations, community_profiles, and
-- community_progress_events present. session_days / study_sessions must
-- NOT be listed.

-- As USER_B, accepted friend of opted-in USER_A:
select user_id from community_progress_events where user_id = 'USER_A';
-- Expect: USER_A's metadata event row only (no session or seconds fields).

-- As USER_B, accepted friend of opted-out USER_A:
select user_id from community_progress_events where user_id = 'USER_A';
-- Expect: zero rows. As anon, select from community_progress_events fails.
```

## 11. Cleanup

```sql
-- Delete test invitations/requests created above; keep real user rows.
```

Record the date, project ref, and pass/fail per step in the release notes.
