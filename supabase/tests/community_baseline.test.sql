-- pgTAP test suite for Community baseline
begin;
select plan(24);

-- 1. Tables exist
select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'sessions', 'sessions table exists');
select has_table('public', 'invites', 'invites table exists');
select has_table('public', 'friendships', 'friendships table exists');
select has_table('public', 'activity_pings', 'activity_pings table exists');
select has_table('public', 'app_waitlist', 'app_waitlist table exists');

-- 2. Functions exist
select has_function('public', 'get_invite_preview', ARRAY['text'], 'get_invite_preview exists');
select has_function('public', 'accept_invite', ARRAY['text'], 'accept_invite exists');
select has_function('public', 'get_community_home', ARRAY['date'], 'get_community_home exists');
select has_function('public', 'get_week_detail', ARRAY['uuid', 'date'], 'get_week_detail exists');
select has_function('public', 'complete_session', ARRAY['integer'], 'complete_session exists');

-- 3. RLS is enabled on all tables
select table_privs_are('public', 'sessions', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'sessions table privs');
select table_privs_are('public', 'profiles', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE'], 'profiles table privs');
select table_privs_are('public', 'invites', 'authenticated', ARRAY['SELECT', 'INSERT'], 'invites table privs');
select table_privs_are('public', 'friendships', 'authenticated', ARRAY['SELECT'], 'friendships table privs');

-- 4. Test preview with invalid token
select is(
  (public.get_invite_preview('invalid-token-123')->>'status'),
  'invalid',
  'invalid token returns invalid status'
);

-- 5. Test preview with empty token
select is(
  (public.get_invite_preview('')->>'status'),
  'invalid',
  'empty token returns invalid status'
);

-- 6. Setup test users and sessions
-- Create mock auth users
insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'userA@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'userB@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'userC@example.com')
on conflict (id) do nothing;

insert into public.profiles (id, name, weekly_goal_minutes)
values
  ('11111111-1111-1111-1111-111111111111', 'User A', 600),
  ('22222222-2222-2222-2222-222222222222', 'User B', 600),
  ('33333333-3333-3333-3333-333333333333', 'User C', 600)
on conflict (id) do update set name = excluded.name;

-- User A has a 120-minute completed session in current week
insert into public.sessions (user_id, started_at, duration_minutes, completed)
values
  ('11111111-1111-1111-1111-111111111111', now(), 120, true);

-- User A creates an invite
insert into public.invites (token, inviter_id)
values ('valid-token-user-a', '11111111-1111-1111-1111-111111111111');

-- Test preview with valid token
select is(
  (public.get_invite_preview('valid-token-user-a')->>'status'),
  'valid',
  'valid token returns valid status'
);

select is(
  (public.get_invite_preview('valid-token-user-a')->>'inviter_name'),
  'User A',
  'inviter_name is returned correctly in preview'
);

-- 7. Test accept invite as User B
-- Set session to User B
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "22222222-2222-2222-2222-222222222222"}';

select is(
  public.accept_invite('valid-token-user-a'),
  'ok',
  'User B accepts User A invite successfully'
);

-- Test reuse of accepted link
select is(
  public.accept_invite('valid-token-user-a'),
  'used',
  'reusing accepted invite returns used'
);

-- Test accept own invite
insert into public.invites (token, inviter_id)
values ('user-b-own-token', '22222222-2222-2222-2222-222222222222');

select is(
  public.accept_invite('user-b-own-token'),
  'own',
  'accepting own invite returns own'
);

-- 8. Test privacy: User B querying sessions directly gets 0 rows for User A
select is(
  (select count(*) from public.sessions where user_id = '11111111-1111-1111-1111-111111111111')::int,
  0,
  'RLS prevents friend from selecting from raw sessions table'
);

-- 9. Test unauthorized week detail: Stranger User C calling get_week_detail for User A throws error
set local "request.jwt.claims" to '{"sub": "33333333-3333-3333-3333-333333333333"}';
select throws_ok(
  $$ select public.get_week_detail('11111111-1111-1111-1111-111111111111', current_date) $$,
  'Access denied: not accepted friends',
  'Stranger calling get_week_detail raises access denied'
);

select * from finish();
rollback;

