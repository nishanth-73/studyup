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
-- Both are re-runnable (IF NOT EXISTS / OR REPLACE / policy drops).
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
-- Expect: USER_B absent.
-- scope='everyone' as USER_A: only opted-in strangers appear.
-- scope='bogus' → ERROR "bad scope".
```

## 8. Session-day validation

```sql
-- Insert a session as USER_A, then session_days rows whose seconds do
-- NOT sum to the segment total → ERROR "split mismatch".
-- Rows for another user_id → ERROR "user mismatch".
```

## 9. Realtime publication

```sql
select tablename from pg_publication_tables where pubname = 'supabase_realtime';
-- Expect: friend_requests, invitations, community_profiles present.
-- session_days / study_sessions must NOT be listed (no broadcast).
```

## 10. Cleanup

```sql
-- Delete test invitations/requests created above; keep real user rows.
```

Record the date, project ref, and pass/fail per step in the release notes.
