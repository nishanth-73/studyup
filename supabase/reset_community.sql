-- ONE-TIME COMMUNITY RESET SCRIPT (REVIEW ONLY - DO NOT RUN AUTOMATICALLY)
--
-- This script explicitly drops ONLY the legacy Community and Social database objects
-- so the database is in a clean baseline state before applying the consolidated migration.
--
-- SAFETY INVARIANTS:
-- 1. Never touches auth.* tables, storage.* buckets, or non-community schemas.
-- 2. Explicitly drops named objects only; does not drop schemas or cascades to other features.
-- 3. Idempotent: safe to run multiple times (uses DROP ... IF EXISTS).

begin;

-- ============================================================================
-- 1. DROP TRIGGERS
-- ============================================================================
drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists trg_materialize_friendship on public.friend_requests;
drop trigger if exists trg_validate_request_transition on public.friend_requests;
drop trigger if exists trg_record_community_progress_change on public.session_days;
drop trigger if exists trg_validate_session_days on public.session_days;

-- ============================================================================
-- 2. DROP TABLES (Reverse dependency order)
-- ============================================================================

-- Obsolete room, presence, challenge features
drop table if exists public.challenge_participants cascade;
drop table if exists public.challenges cascade;
drop table if exists public.room_presence cascade;
drop table if exists public.room_invites cascade;
drop table if exists public.study_rooms cascade;

-- Realtime events (obsolete)
drop table if exists public.community_progress_events cascade;

-- Moderation & blocks
drop table if exists public.moderation_reports cascade;
drop table if exists public.blocks cascade;

-- Invitations & friendships
drop table if exists public.invitation_acceptances cascade;
drop table if exists public.invitations cascade;
drop table if exists public.friend_requests cascade;
drop table if exists public.friendships cascade;

-- Sessions & day splits
drop table if exists public.session_days cascade;
drop table if exists public.study_sessions cascade;

-- Community user profiles
drop table if exists public.community_profiles cascade;

-- ============================================================================
-- 3. DROP FUNCTIONS (Explicitly typed signatures)
-- ============================================================================

-- Presence & rooms
drop function if exists public.sweep_stale_presence();

-- Friend requests & friendships
drop function if exists public.accept_friend_request(uuid);
drop function if exists public.validate_request_transition();
drop function if exists public.materialize_friendship();
drop function if exists public.community_are_friends(uuid, uuid);
drop function if exists public.my_friends();

-- Blocks & moderation
drop function if exists public.community_are_blocked(uuid, uuid);
drop function if exists public.block_user(uuid);
drop function if exists public.report_user(uuid, text, text);

-- Profiles
drop function if exists public.handle_new_user();
drop function if exists public.update_community_profile(text, text, integer, integer, boolean);

-- Invitations
drop function if exists public.create_invitation(text, timestamptz);
drop function if exists public.create_invitation();
drop function if exists public.invitation_preview(text);
drop function if exists public.accept_invitation(text);
drop function if exists public.revoke_invitation(uuid);

-- Sessions & validation
drop function if exists public.session_total_seconds(jsonb);
drop function if exists public.validate_session_days();
drop function if exists public.upload_study_session(text, text, text, timestamptz, timestamptz, jsonb);

-- Leaderboards & progress
drop function if exists public.community_timezone();
drop function if exists public.community_week_start(timestamptz);
drop function if exists public.leaderboard_scope(text, timestamptz, timestamptz);
drop function if exists public.get_weekly_leaderboard(timestamptz, timestamptz);
drop function if exists public.daily_rows(uuid, date, date);
drop function if exists public.record_community_progress_change();

-- User search (obsolete)
drop function if exists public.search_users(text);

commit;

