# StudyUP Community Feature Specification (v2.0)

## 1. Executive Summary & Goals

StudyUP Community is a private, mutual-friend study circle and weekly motivation board designed to encourage consistent study habits without the toxicity, privacy invasion, or maintenance overhead of a public social network.

### Primary Goals
1. **Private Study Circles:** Only mutual friends who have connected via explicit invite links appear on a user's leaderboard. There is no global public board and no directory browsing.
2. **Frictionless Invitation via Native Sharing:** Any student can tap "Invite Friend" to generate a short invite link and dispatch it via the native Android/iOS system share sheet (WhatsApp, Telegram, SMS, etc.).
3. **Plausibility & Integrity Without Surveillance:** The app operates offline-first. Offline study sessions are uploaded with server-side validation against physical plausibility limits (no >16h/day, no overlaps, skew limits) rather than invasive realtime monitoring or battery-draining heartbeats.
4. **Clean, Minimal Data Architecture:** Strict least-privilege security model in Supabase: no direct client table writes, hardened SECURITY DEFINER RPCs with empty `search_path`, hash-only invite storage, and zero orphaned features.

---

## 2. Canonical Week & Timezone Policy

### Fixed Canonical Timezone
- **Timezone:** `Asia/Kolkata` (`+05:30` UTC offset, invariant all year; India does not observe Daylight Saving Time).
- All daily boundaries (00:00:00 to 23:59:59.999) and weekly boundaries are calculated strictly in `Asia/Kolkata`.
- Database helper: `public.community_timezone() RETURNS text` returns `'Asia/Kolkata'`.

### Canonical Week Window
- A week begins on **Monday at 00:00:00.000 Asia/Kolkata** (inclusive) and ends on the next **Monday at 00:00:00.000 Asia/Kolkata** (exclusive).
- Duration: Exactly 7 days (168 hours).
- Canonical calculation function:
  ```sql
  public.community_week_start(p_instant timestamptz) RETURNS timestamptz
  ```
  Returns `date_trunc('week', p_instant AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'`.
- All weekly leaderboard queries strictly require `p_start = community_week_start(p_start)` and `p_end = p_start + interval '168 hours'`. Arbitrary or rolling date ranges are rejected by the server (`22000`).

---

## 3. Leaderboard Ranking & Tie-Break Rules

### Eligibility
A user appears on caller's leaderboard if and only if:
1. `user_id = auth.uid()` (the caller themselves), OR
2. A confirmed mutual friendship exists in `public.friendships` between caller and user, AND
3. Neither user has blocked the other in `public.blocks`.

### Ranking Formula & Tie-Breaks
Users are ranked strictly according to the following order:
1. **Primary Sort:** `week_seconds DESC` (total server-validated study seconds within the canonical week).
2. **Primary Tie-Break:** `display_name ASC` (case-insensitive alphabetical order).
3. **Deterministic Tie-Break:** `user_id ASC` (guarantees rock-solid, deterministic ordering across queries).

### Zero-Minute Friends
- Friends who studied 0 minutes in the selected week **are always included** on the leaderboard (ranked at the bottom, ordered by display name).
- This ensures friends never "disappear" or appear dropped from the circle when they haven't logged study time yet.

### Presentation: Podium vs. List
- **Podium (Top 3):**
  - Rank 1: Gold Crown / Highlight
  - Rank 2: Silver Highlight
  - Rank 3: Bronze Highlight
- If the friend circle has fewer than 3 total participants, empty podium slots are presented as accessible "Open spots" with a direct CTA button to "Invite Friend".
- **List View:** All ranks from 4th downward render in an accessible list with rank numbers, avatar, name, and weekly study hours/minutes.

---

## 4. Study Session Validity Limits (Plausibility Barrier)

StudyUP operates offline-first: completed study sessions are recorded locally on device and synced when connected. To prevent client spoofing or accidental corrupt records from polluting leaderboards, the server enforces strict validation rules via `public.upload_study_session`:

| Rule | Limit | Violation Handling |
| :--- | :--- | :--- |
| **Max Daily Study** | 16 hours (57,600 seconds) per calendar day in `Asia/Kolkata` | Rejects session upload (`22000`) |
| **Future Skew** | Max 5 minutes in the future (`now() + interval '5 minutes'`) | Rejects session upload (`22000`) |
| **Historical Age** | Sessions starting older than 14 days (336 hours) | Rejects session upload (`22000`) |
| **Minimum Interval** | Each segment must have `ends_at > starts_at` (>= 1 second) | Rejects session upload (`22000`) |
| **Segment Count** | Between 1 and 500 segments per session | Rejects session upload (`22000`) |
| **Internal Overlap** | Segments within the same session payload cannot overlap | Rejects session upload (`22000`) |
| **Cross-Session Overlap** | Segments cannot overlap any previously validated session for that user | Rejects session upload (`22000`) |
| **Idempotency** | Re-upload of an identical session payload by the same owner | No-op success (returns immediately) |

### Server-Side Day Splitting
Sessions that cross local midnight (Asia/Kolkata) are deterministically split across calendar days by the server during `upload_study_session`, populating `public.session_days` with `server_validated = true`. Clients never directly insert into `session_days`.

---

## 5. Sharing Defaults & Privacy Policy

### Default Settings
- `leaderboard_opt_in = true` by default upon account creation.
- Default weekly goal: `300 minutes` (5 hours).

### What is Shared With Friends (When Opted In)
- `display_name` (trimmed text, 1–48 characters)
- `avatar_id` (identifier string, e.g. `'robo-default'`)
- `blob_variant` (integer 0–3 representing customized robot style)
- `week_seconds` (aggregated study seconds for the active week)
- `active_days` (count of distinct days studied this week)
- `total_seconds` (all-time verified study seconds)
- `streak_days` (current consecutive daily study streak)

### What is NEVER Shared
- Raw session timestamps (`check_in`, `check_out`, individual segments)
- Specific subject names, notes, task names, or syllabus progress
- User email, phone numbers, or authentication identities
- IP addresses, device metadata, or geolocations

### Opt-Out Behavior
If a user switches off `leaderboard_opt_in` (via `update_community_profile`):
- Their study stats (`week_seconds`, `active_days`, `total_seconds`, `streak_days`) are returned as `0` to all friends.
- They remain visible in their friends' lists as a connected friend (with 0m shown).
- The user can always see their own genuine stats when querying the leaderboard as caller (`auth.uid() = id`).

---

## 6. Invitation Lifecycle & Mechanics

```
[ User A taps "Invite" ] 
         │
         ▼
[ Server RPC: create_invitation ]
  - Generates 32-byte crypto-random token
  - Stores sha256(token) in public.invitations
  - Sets expires_at = now() + 7 days
  - Enforces quota (max 20 active invitations)
  - Returns raw token to client
         │
         ▼
[ Native Share Sheet (WhatsApp, SMS, etc.) ]
  - Sends URL: https://studyup.guru/i/<token>
         │
         ▼
[ User B opens Link ] 
         │
         ▼
[ Server RPC: invitation_preview ]
  - Verifies token hash, expiration, and blocks
  - Returns inviter display_name & avatar_id
         │
         ▼
[ User B taps "Accept" ]
         │
         ▼
[ Server RPC: accept_invitation ]
  - Verifies token not expired, not revoked, not self-invite
  - Verifies no active block between users
  - Atomically creates mutual friendship in public.friendships
  - Records acceptance in public.invitation_acceptances
  - Updates invitation status to 'accepted'
  - Idempotent: repeated accept by same user returns friend without error
```

### Key Invitation Rules
1. **Server-Generated Tokens:** Clients never generate tokens. The server generates 32 bytes from `extensions.gen_random_bytes(32)`, encodes as hex, stores `encode(digest(token, 'sha256'), 'hex')`, and returns the clear token once to the caller.
2. **Hash-Only Storage:** Database only stores the SHA-256 digest (`token_hash`). If the database is compromised, invitations cannot be spoofed.
3. **Expiration:** Strictly 7 days (`expires_at = clock_timestamp() + interval '7 days'`). Expired tokens cannot be previewed or accepted.
4. **Active Quota:** Maximum 20 active invitations per user. Prevents link-spamming or denial-of-service abuse.
5. **Single Use:** `max_uses = 1`. Once accepted, status becomes `'accepted'`.
6. **Creator Revocation:** Creator can revoke any active invite at any time via `revoke_invitation(invitation_id)`.
7. **Mutual Friendship:** Friendships are bidirectional. Stored as `(user_low, user_high)` where `user_low < user_high` using PostgreSQL `least()` and `greatest()`.

---

## 7. Blocks & Moderation

### Blocks Architecture (`public.blocks`)
- Any authenticated user can block any other user via `block_user(p_user_id)`.
- When user A blocks user B:
  1. Row `(A, B)` is inserted into `public.blocks`.
  2. Any existing friendship between A and B in `public.friendships` is immediately deleted.
  3. Any active invitations between them are rendered invalid.
  4. Neither user can see the other on leaderboards or friend lists.
  5. The check `community_are_blocked(a, b)` returns `true` if either side blocked the other.

### Moderation Reports (`public.moderation_reports`)
- Users can report abusive display names or misconduct via `report_user(p_reported_id, p_reason, p_details)`.
- Stored securely with RLS for review by system operators.

---

## 8. Complete Data Model & RPC Signatures

### Tables

```sql
-- 1. User Community Profiles
create table public.community_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  avatar_id text not null default 'robo-default',
  blob_variant integer not null default 0,
  weekly_goal_minutes integer not null default 300,
  leaderboard_opt_in boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint community_profiles_display_name_check check (char_length(btrim(display_name)) between 1 and 48),
  constraint community_profiles_avatar_id_check check (char_length(btrim(avatar_id)) between 1 and 80),
  constraint community_profiles_blob_variant_check check (blob_variant between 0 and 3),
  constraint community_profiles_weekly_goal_minutes_check check (weekly_goal_minutes between 60 and 10080)
);

-- 2. Bidirectional Friendships (Canonical Pair)
create table public.friendships (
  user_low uuid not null references auth.users (id) on delete cascade,
  user_high uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_low, user_high),
  constraint friendships_order_check check (user_low < user_high)
);

-- 3. Invitations (Hash-Only Storage)
create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users (id) on delete cascade,
  token_hash text not null unique,
  max_uses integer not null default 1,
  uses integer not null default 0,
  status text not null default 'active',
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint invitations_status_check check (status in ('active', 'accepted', 'expired', 'revoked'))
);

-- 4. Invitation Acceptances (Audit & Idempotency)
create table public.invitation_acceptances (
  id uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.invitations (id) on delete cascade,
  accepted_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (invitation_id, accepted_by)
);

-- 5. Study Sessions (Verified via RPC only)
create table public.study_sessions (
  id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  subject_id text not null,
  subject_name text not null,
  check_in timestamptz not null,
  check_out timestamptz not null,
  paused_seconds integer not null default 0,
  segments jsonb not null,
  server_validated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 6. Session Days (Server-Generated Daily Splits)
create table public.session_days (
  session_id text not null references public.study_sessions (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  day_start_utc timestamptz not null,
  seconds integer not null,
  server_validated boolean not null default false,
  primary key (session_id, day)
);

-- 7. User Blocks
create table public.blocks (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_no_self_block check (blocker_id <> blocked_id)
);

-- 8. Moderation Reports
create table public.moderation_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users (id) on delete cascade,
  reported_id uuid not null references auth.users (id) on delete cascade,
  reason text not null,
  details text,
  created_at timestamptz not null default now()
);
```

---

### RPC Specifications

#### 1. `create_invitation`
- **Signature:** `public.create_invitation() RETURNS TABLE (invitation_id uuid, token text, expires_at timestamptz)`
- **Behavior:**
  - Verifies caller is authenticated.
  - Checks active invite quota (< 20 active).
  - Generates 32-byte crypto token.
  - Computes `sha256(token)`.
  - Inserts row with `expires_at = now() + interval '7 days'`.
  - Returns `invitation_id`, cleartext `token`, and `expires_at`.

#### 2. `invitation_preview`
- **Signature:** `public.invitation_preview(p_token text) RETURNS TABLE (display_name text, avatar_id text, valid boolean, reason text)`
- **Behavior:**
  - Hashes `p_token`.
  - Look up invitation and creator profile.
  - Returns `valid = false` if not found, expired, revoked, already used, or if either side blocked the other.
  - Returns creator's `display_name` and `avatar_id` on success.
  - Callable by `anon` and `authenticated` (so prospective students can view invite preview before signing in).

#### 3. `accept_invitation`
- **Signature:** `public.accept_invitation(p_token text) RETURNS TABLE (friend_id uuid, display_name text)`
- **Behavior:**
  - Verifies caller is authenticated.
  - Takes transaction advisory lock on `(auth.uid(), creator_id)` to prevent race conditions.
  - Verifies token validity and checks neither party is blocked.
  - Verifies not self-invite (`auth.uid() != creator_id`).
  - Idempotently creates friendship in `public.friendships`.
  - Records acceptance in `public.invitation_acceptances`.
  - Marks invitation `status = 'accepted'`.
  - Returns friend ID and display name.

#### 4. `revoke_invitation`
- **Signature:** `public.revoke_invitation(p_invitation_id uuid) RETURNS void`
- **Behavior:**
  - Marks caller's active invitation as `'revoked'`.

#### 5. `upload_study_session`
- **Signature:** `public.upload_study_session(p_session_id text, p_subject_id text, p_subject_name text, p_check_in timestamptz, p_check_out timestamptz, p_segments jsonb) RETURNS void`
- **Behavior:**
  - Validates session parameters: non-empty IDs, valid timestamp ranges, no future skew (> 5 min), age <= 14 days, segment count 1..500.
  - Checks internal segments for zero duration and internal overlaps.
  - Verifies no cross-session overlap against caller's prior sessions.
  - Verifies that day splits do not exceed 16 hours in any single Asia/Kolkata day.
  - Upserts into `public.study_sessions` with `server_validated_at = clock_timestamp()`.
  - Computes and inserts day splits into `public.session_days` with `server_validated = true`.

#### 6. `get_weekly_leaderboard` (replacing/aliasing `leaderboard_scope`)
- **Signature:** `public.get_weekly_leaderboard(p_start timestamptz, p_end timestamptz) RETURNS TABLE (user_id uuid, display_name text, avatar_id text, blob_variant integer, week_seconds bigint, active_days bigint, total_seconds bigint, streak_days integer)`
- **Behavior:**
  - Requires caller authentication.
  - Validates that `p_start` is canonical Monday 00:00 Asia/Kolkata and `p_end = p_start + interval '168 hours'`.
  - Collects eligible user IDs: `auth.uid()` + confirmed mutual friends (excluding blocked users).
  - Merges and clips validated session segments falling within `[p_start, p_end)`.
  - Computes `week_seconds`, `active_days`, `total_seconds`, and consecutive day `streak_days`.
  - Respects `leaderboard_opt_in`: masks stats to 0 if opted out (caller always sees their own stats).
  - Orders by `week_seconds DESC, display_name ASC, user_id ASC`.
  - Limits to 100 entries.

#### 7. `daily_rows`
- **Signature:** `public.daily_rows(p_user_id uuid, p_from date, p_to date) RETURNS TABLE (day date, seconds integer)`
- **Behavior:**
  - Returns daily study seconds for `p_user_id` between `p_from` and `p_to` (max range 730 days).
  - Allowed only if `p_user_id = auth.uid()` or mutual friends with `leaderboard_opt_in = true`.

#### 8. `update_community_profile`
- **Signature:** `public.update_community_profile(p_display_name text, p_avatar_id text, p_blob_variant integer, p_weekly_goal_minutes integer, p_share_weekly_progress boolean) RETURNS void`
- **Behavior:**
  - Validates constraints (name 1..48 chars, avatar 1..80 chars, variant 0..3, goal 60..10080 min).
  - Updates caller's row in `public.community_profiles`.

#### 9. `block_user`
- **Signature:** `public.block_user(p_user_id uuid) RETURNS void`
- **Behavior:**
  - Adds block, severs friendship in `public.friendships`, cancels any pending interaction.

#### 10. `my_friends`
- **Signature:** `public.my_friends() RETURNS TABLE (friend_id uuid, display_name text, avatar_id text, blob_variant integer, created_at timestamptz)`
- **Behavior:**
  - Returns list of confirmed mutual friends (excluding any blocked users).

---

## 9. Security Rules (RLS & Grants)

### Principle of Least Privilege
1. **Zero Direct Client Table Writes:**
   - `INSERT`, `UPDATE`, `DELETE` are completely revoked from `public`, `anon`, and `authenticated` on:
     - `public.community_profiles`
     - `public.friendships`
     - `public.invitations`
     - `public.invitation_acceptances`
     - `public.study_sessions`
     - `public.session_days`
     - `public.moderation_reports`
   - All mutations occur strictly through the vetted SECURITY DEFINER RPCs.
2. **Selective Column Grants on Read:**
   - `community_profiles`: Authenticated users can only `SELECT` safe profile columns (`id, display_name, avatar_id, blob_variant, leaderboard_opt_in, weekly_goal_minutes`).
   - `invitations`: Creators can only `SELECT` metadata (`id, created_by, created_at, expires_at, max_uses, uses, status`). Column `token_hash` is **never granted** for reading.
   - `blocks`: Authenticated users can `SELECT`, `INSERT`, `DELETE` only their own rows (`auth.uid() = blocker_id`).
3. **Hardened SECURITY DEFINER Functions:**
   - Every SECURITY DEFINER function sets `search_path = ''` to prevent search path injection attacks.
   - All referenced objects are schema-qualified (`public.`, `pg_catalog.`, `extensions.`).
   - Every `RETURNS TABLE` function uses `#variable_conflict use_column` to eliminate parameter/column collision warnings.
   - All functions revoke permissions from `public` and `anon` by default, explicitly granting execute to `authenticated` (and `anon` solely for `invitation_preview`).

---

## 10. Offline & Retry Behavior

1. **Local-First Authority:** Local SQLite and SharedPreferences remain the immediate and authoritative record of all study sessions on device.
2. **Idempotent Sync Queue:**
   - When a session ends or the app launches, unsynced sessions are queued for upload via `upload_study_session`.
   - The session ID is a stable client UUID (`s-<timestamp>`).
   - If a retry occurs due to network interruption, the server detects the identical session payload and succeeds idempotently without duplicate rows or errors.
3. **Offline Acceptance of Invites:**
   - If an invite link is opened while offline, the app stores the token in local preferences (`PendingInviteUiState.token`).
   - Once online connectivity is restored and the user signs in, the pending token is automatically submitted.

---

## 11. Refresh & Polling Policy

To maximize battery life and eliminate realtime connection thrashing:
1. **No Realtime Subscriptions:** Supabase Realtime channels (WebSockets) are intentionally not used for community leaderboards.
2. **Deterministic Refresh Triggers:**
   - **Post-Action:** Immediate refetch after accepting an invite, blocking a user, or completing session upload.
   - **App Resume:** Refetch when the app returns from background to foreground.
   - **Tab Navigation:** Refetch when switching to the Community tab if data is older than 60 seconds.
   - **Pull to Refresh:** Standard `RefreshIndicator` gesture on the Community screen.
   - **Foreground Polling:** Low-frequency 30–60 second timer active **only** while the Community screen is currently in view.
3. **Honest Copy:** UI and documentation explicitly state: "Leaderboard updates periodically; no instant live-stream claim".

---

## 12. What is EXCLUDED (Out of Scope)

The following legacy concepts are permanently excluded to preserve privacy, reliability, and code simplicity:
- **No Global / Public Leaderboards:** No worldwide rank lists or strangers' data.
- **No Study Rooms:** No video/audio rooms, no room presence, no room invites (`study_rooms`, `room_presence`, `room_invites`).
- **No Unilateral Friend Requests:** Replaced entirely by tokenized invitation links (`friend_requests` dropped).
- **No Live "Currently Studying" Heartbeats:** No battery-draining presence broadcasting.
- **No Challenges Engine:** No complex multi-user group challenges or participant stakes (`challenges`, `challenge_participants`).
- **No Directory User Search:** No arbitrary name search across all registered accounts (`search_users` dropped).
- **No Direct Messaging:** No in-app chat or messaging.

---

## 13. SQL Object Disposition Table

Every SQL object across migrations `20261015` through `20261116` is cataloged below with its disposition in the clean baseline:

| Object Name | Object Type | Migration Origin | Action | Rationale |
| :--- | :--- | :--- | :--- | :--- |
| `public.community_profiles` | Table | `20261015` | **Merge / Retain** | Core user community identity and opt-in preferences. Lockdown direct writes. |
| `public.friendships` | Table | `20261015` | **Merge / Retain** | Bidirectional confirmed mutual friend links (`user_low < user_high`). |
| `public.invitations` | Table | `20261102` | **Merge / Retain** | Tokenized invite links. Hash-only storage, 7-day expiry. |
| `public.invitation_acceptances` | Table | `20261115` | **Merge / Retain** | Audit trail and idempotency barrier for accepted invites. |
| `public.study_sessions` | Table | `20261102` | **Merge / Retain** | Verified session storage. Lockdown direct writes; updated via RPC only. |
| `public.session_days` | Table | `20261102` | **Merge / Retain** | Deterministic Asia/Kolkata daily splits. Written exclusively by server RPC. |
| `public.blocks` | Table | `20261116` | **Merge / Retain** | User block list severs friendships and prevents contact. |
| `public.moderation_reports` | Table | `20261015` | **Merge / Retain** | Simple reporting mechanism for safety. |
| `public.friend_requests` | Table | `20261015` | **DROP** | Obsolete. Replaced by tokenized invite links (`invitations`). |
| `public.study_rooms` | Table | `20261015` | **DROP** | Excluded feature. No rooms in StudyUP. |
| `public.room_invites` | Table | `20261015` | **DROP** | Excluded feature. |
| `public.room_presence` | Table | `20261015` | **DROP** | Excluded feature. |
| `public.challenges` | Table | `20261015` | **DROP** | Excluded feature. No challenges engine. |
| `public.challenge_participants` | Table | `20261015` | **DROP** | Excluded feature. |
| `public.community_progress_events` | Table | `20261113` | **DROP** | Obsolete realtime events table. Realtime removed. |
| `public.community_timezone()` | Function | `20261116` | **Merge / Retain** | Returns `'Asia/Kolkata'`. Immutable helper. |
| `public.community_week_start(timestamptz)` | Function | `20261116` | **Merge / Retain** | Calculates canonical Monday 00:00 Asia/Kolkata boundary. |
| `public.create_invitation()` | Function | `20261102` | **Merge / Update** | Updated: Server-generated 32-byte crypto token, 20-active quota, hash-only. |
| `public.invitation_preview(text)` | Function | `20261102` | **Merge / Update** | Updated: Empty search path, digest qualification, block awareness. |
| `public.accept_invitation(text)` | Function | `20261102` | **Merge / Update** | Updated: Advisory lock, block awareness, idempotent acceptances. |
| `public.revoke_invitation(uuid)` | Function | `20261116` | **Merge / Retain** | Allows inviter to revoke active invite link. |
| `public.upload_study_session(...)` | Function | `20261116` | **Merge / Retain** | Primary session ingestion RPC. Enforces 16h/day, 14-day window, no overlaps. |
| `public.leaderboard_scope(...)` | Function | `20261102` | **Merge / Rename** | Consolidated into `get_weekly_leaderboard` (with alias if needed). |
| `public.get_weekly_leaderboard(...)` | Function | New Baseline | **Create** | Canonical weekly friends leaderboard RPC with deterministic tie-breaks. |
| `public.daily_rows(uuid, date, date)` | Function | `20261102` | **Merge / Retain** | Aggregate daily study time for self or mutual opted-in friends. |
| `public.my_friends()` | Function | `20261102` | **Merge / Retain** | Returns mutual friends list excluding blocked users. |
| `public.update_community_profile(...)` | Function | `20261116` | **Merge / Retain** | Only client write path for community profile settings. |
| `public.block_user(uuid)` | Function | `20261116` | **Merge / Retain** | Adds block, severs friendship, cancels pending invites. |
| `public.report_user(uuid, text, text)` | Function | New Baseline | **Create** | Inserts moderation report safely. |
| `public.community_are_friends(uuid, uuid)` | Function | `20261015` | **Merge / Update** | Stable check incorporating blocks check. |
| `public.community_are_blocked(uuid, uuid)` | Function | `20261116` | **Merge / Retain** | Stable block check between two users. |
| `public.handle_new_user()` | Function / Trigger | `20261102` | **Merge / Retain** | Triggers on `auth.users` insert to create default community profile. |
| `public.session_total_seconds(jsonb)` | Function | `20261102` | **Merge / Retain** | Helper function summing segment durations. |
| `public.accept_friend_request(uuid)` | Function | `20261015` | **DROP** | Obsolete. Friend requests table dropped. |
| `public.validate_request_transition()` | Function | `20261102` | **DROP** | Obsolete. Friend requests table dropped. |
| `public.materialize_friendship()` | Function | `20261102` | **DROP** | Obsolete. Friendships materialized in `accept_invitation`. |
| `public.validate_session_days()` | Function | `20261102` | **DROP** | Obsolete. Days generated server-side in `upload_study_session`. |
| `public.sweep_stale_presence()` | Function | `20261015` | **DROP** | Obsolete. Presence table dropped. |
| `public.record_community_progress_change()` | Function | `20261113` | **DROP** | Obsolete. Realtime events table dropped. |
| `public.search_users(text)` | Function | `20261102` | **DROP** | Obsolete. Global search dropped for privacy. |
