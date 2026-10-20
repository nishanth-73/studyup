# StudyUp Supabase backend — connect, configure, verify

The Flutter app ships with the **complete social backend integration**:
client, required authentication, migrations, RLS, invitation links,
session sync, and the Community UI read from Supabase. Offline guest
access is not available; a configured backend and network are required
to enter protected app features. No service-role key is shipped in the
app.

## A. What is implemented and locally tested

- `lib/core/backend/` — `supabase_config.dart` (dart-define config, no
  hardcoding) + `supabase_client.dart` (single client, graceful startup
  when configuration is missing). Authentication and protected features
  require a configured backend and network; local data is not uploaded
  without an authenticated account. Nothing fakes successful sign-in.
- `lib/features/auth/` — real email/password auth (`AuthRepository`,
  `auth_controller.dart`): sign up, sign in, email verification +
  resend, password reset, sign out, session restore, auth-state stream.
  Protected routes require a restored Supabase session and account-owned
  local data. Sign-in syncs local history idempotently and resumes pending
  invite tokens.
- `supabase/migrations/20261015_community.sql` — existing tables/policies
  (friends, requests, rooms, challenges, presence).
- `supabase/migrations/20261102_social_backend.sql` — profile
  auto-create trigger, `invitations` (hash-only tokens), hardened
  request-transition triggers, friendship materialization,
  `study_sessions` + validated `session_days`, `leaderboard_scope`,
  `daily_rows`, `my_friends`, `search_users`, `create/accept/preview`
  invitation RPCs, realtime publication entries. Repeatable, no resets.
- `supabase/migrations/20261113_community_progress_realtime.sql` —
  accepted-friend-only, opt-in-aware aggregate access and a metadata-only
  progress event table for friend-scoped realtime invalidation. Raw study
  sessions and per-session day rows are never published.
- `supabase/migrations/20261114_community_weekly_dedup.sql` — corrects
  friend leaderboard weekly totals by clipping intervals to the requested
  Monday-to-Monday window and merging overlapping sessions before summing.
  Friendship controls who may read the aggregate, not when eligible study
  time was recorded.
- `supabase/migrations/20261115_invitation_acceptance_idempotency.sql` —
  records the authenticated recipient of a completed accept so retries after
  a lost response are safe without allowing another account to reuse a
  single-use invitation.
- `lib/features/social/` — `SocialRemote` (all Supabase queries),
  `SessionSyncService` (idempotent upload, local persistence remains
  authoritative), providers (live gating, friend-scoped realtime
  invalidation, lifecycle refresh, and retry fallback).
- Community — live server leaderboard (friends scope of
  `leaderboard_scope`), podium/comparison/rows from one selected-week
  ranking; the picker browses past weeks, Monday 00:00 through the
  following Monday 00:00 in the viewing device's local timezone (converted
  to UTC for the RPC); demo
  fixtures only offline.
- Friends — live friends list, incoming requests (realtime),
  display-name search, send/accept/decline/cancel, remove; privacy
  toggles mirrored server-side.
- Invitations — one shareable link per invitation,
  `https://HOST/i/<code>` (32-char hex code, never the offline `SUP1`
  payload): the browser landing page (`public/index.html`) for recipients
  without the app — invitation text, a **Download StudyUp** button driven
  by `public/apk.json` (code preserved as `?invite=<code>`), and an
  explicit "not configured yet" note instead of any invented store link.
  With the app installed the same link opens the app (Android App Links,
  custom-scheme `studyup://invite/` fallback) onto the accept screen,
  which shows the inviter's name and offers **Accept invitation** /
  **Decline**. Opening a link never accepts: the friendship is created
  server-side only by `accept_invitation` after the user taps Accept, and
  `create_invitation` stamps `created_by = auth.uid()` so neither the
  code nor a tampered URL can join someone else's Community. Native share
  sheet via `share_plus`.
   Android App Link intent-filter (primary host the main production
   domain `studyup-4x7z.vercel.app`;
   earlier `studyup-feedback-api.vercel.app` and legacy
   `invite.studyup.app` also accepted, autoVerify) plus
   `studyup://invite/` fallback;
  `supabase/assetlinks/` template, deployed from
  `public/.well-known/assetlinks.json`.
- Auth callbacks — `com.studyup.studyup://login-callback/` custom-scheme
  intent-filter; supabase_flutter auto-exchanges OAuth/email codes for
  sessions; Google OAuth wired in `AuthRepository.signInWithGoogle`.
- Tests — `test/supabase_link_test.dart` (config, token gen/hash,
  link build/parse, day splits), `test/supabase_auth_link_test.dart`
  (exact callback URL, scheme/package match, auth-vs-invite routing,
  error mapping) pass; full suite green; debug APK builds.

## B. Awaiting YOUR Supabase project (credentials)

1. Create the project at https://supabase.com/dashboard (free tier is
   fine). Note the **Project URL** and **anon public key**
   (Project Settings → API). Enable Email auth
   (Authentication → Providers → Email, confirm-email ON recommended).
2. **Allowed Redirect URLs — REQUIRED for login to return to the app.**
   Go to Authentication → URL Configuration → Allowed Redirect URLs and
   add EXACTLY this line (no trailing spaces, keep the trailing slash):
   ```
   com.studyup.studyup://login-callback/
   ```
   Why: the scheme is the Android `applicationId`
   (`android/app/build.gradle.kts`), and the manifest already contains
   the matching intent-filter, so Supabase redirects (Google OAuth,
   email confirmation, password recovery) open StudyUp directly and
   `supabase_flutter` completes sign-in automatically. Without this
   entry Supabase blocks the redirect and the browser flow dead-ends.
   (Optional: also add your Site URL for web-based flows.)
3. **Google OAuth provider (for the Continue with Google button).**
   a. Google Cloud Console (https://console.cloud.google.com) → create a
      project → APIs & Services → Credentials → Create Credentials →
      OAuth client ID → **Android**: package name `com.studyup.studyup`
      plus your SHA-1 certificate fingerprint (debug: `keytool -list -v
      -keystore ~/.android/debug.keystore -alias androiddebugkey
      -storepass android -keypass android`; release: your upload
      keystore). Also create a **Web application** OAuth client.
   b. Supabase Dashboard → Authentication → Providers → Google →
      enable, paste the Web client **Client ID** and **Client Secret**.
   c. The app calls `signInWithOAuth(google, redirectTo:
      com.studyup.studyup://login-callback/)`, so no extra Android
      config is needed beyond the intent-filter already present.
4. SQL editor → run `supabase/migrations/20261015_community.sql`,
   `supabase/migrations/20261102_social_backend.sql`,
   `supabase/migrations/20261104_hardening_fix.sql`,
   `supabase/migrations/20261112_friends_zero_progress.sql`, and
   `supabase/migrations/20261113_community_progress_realtime.sql`,
   `supabase/migrations/20261114_community_weekly_dedup.sql`, and
   `supabase/migrations/20261115_invitation_acceptance_idempotency.sql`,
   in that order.
   The third file is **required**: without it
   `invitation_preview`/`accept_invitation` fail with
   `"function digest(text, unknown) does not exist"`, so the whole
   invitation flow is broken.
   Keep historical files intact if they may already be recorded as applied.
   The final migration is forward-only; this code change has not applied or
   verified it against production.
5. Run the app with your values (never commit them):
   ```sh
   flutter run \
     --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
   ```
   Release builds need the same `--dart-define`s on `flutter build`.
   Optional: `--dart-define=INVITE_HOST=invite.example.com`,
   `--dart-define=INVITE_SCHEME=studyup`.
6. Sign up in the app → tap the link in the verification email (it
   reopens StudyUp via the callback above) → log in, or use Continue
   with Google (browser → back to the app automatically). Local history
   syncs automatically (idempotent). Community uses server-backed friend
   totals. If Supabase credentials or network access are unavailable,
   authentication and protected features cannot be used.
7. Work through `supabase/tests/verify_rls.md` and record results.

`.env.example` documents the variables; `.env*` is git-ignored.

## C. Awaiting external hosting/domain/signing/store setup

These cannot be completed without your domain + signing keys + store
presence. The app is fully coded for them; only configuration remains.

1. **Invite domain**: the App Links host is the main production
   domain `studyup-4x7z.vercel.app` (`INVITE_HOST` default; override with
   `--dart-define=INVITE_HOST=...` for a custom domain). Use that stable
   domain, never a per-deployment URL
   (`studyup-4x7z-<hash>-...vercel.app`): deployment URLs change on
   every deploy, so previously shared links would keep pointing at an
   older build. FIRST disable Vercel Deployment Protection (Project →
   Settings → Deployment Protection → Vercel Authentication →
   Disabled): while it is on, anonymous visitors, Android App Links
   verification and the app's feedback requests are all redirected to
   a Vercel login page. The same Vercel project must serve
   `/.well-known/assetlinks.json`; `public/.well-known/assetlinks.json`
   is the deployed copy (kept identical to
   `supabase/assetlinks/assetlinks.json`; `node --test
   assetlinks.test.js` in `api/` verifies both) plus the hosted landing
   page. `public/index.html` serves both the general landing page and
   the invitation fallback: `vercel.json` rewrites `/i/:token` (and
   `/invite/:token`) to it, so non-Android/desktop visitors get a usable
   page instead of a 404. On Android the page shows an `intent://`
   button (scheme `studyup`, package `com.studyup.studyup`, browser
   fallback = the page itself); other platforms get a copy-link hint.
   The page never accepts an invitation — tokens stay pending until the
   recipient taps Accept inside the app. The APK button stays disabled
   until `public/apk.json` gets a real `apkUrl` (https, non-debug); no
   fake download link is rendered. Deploy with `vercel --prod` (Vercel
   serves `public/` automatically). `api/landing.test.js` guards all of
   this (self-contained, no secrets, token-guarded script).
2. **Android association**: `AndroidManifest.xml` already lists the
   primary host plus the legacy `invite.studyup.app` (kept so links
   shared before the switch still open the app when verified; hosts
   verify independently). Fingerprints — debug SHA-256 is filled in
   and is currently also what `flutter build apk --release` uses
   (`build.gradle.kts` still signs release with the debug keystore):
   ```
   9B:F3:A6:6B:41:18:25:FC:7B:C5:3B:CB:AF:55:F9:55:42:8D:56:26:B4:AC:DF:7E:20:0B:3D:7C:B4:C3:AB:E0
   ```
   When you add a real release keystore (Android Studio → Build →
   Generate Signed App Bundle, or `keytool`), append its SHA-256 from
   `.\gradlew signingReport`. After Play enrollment, the effective
   release fingerprint is Play App Signing's, found in Play Console →
   your app → **Test and release → App integrity → App signing key
   certificate → SHA-256**. Add it to `public/.well-known/assetlinks.json`
   AND `supabase/assetlinks/assetlinks.json`, commit, and
   `vercel --prod` (App Links only verify after the deployed file
   matches).
3. **Store listing**: publish (or draft) the Play listing; the web
   fallback page and share text should point at it. Set
   `public/apk.json → apkUrl` (https, never a debug build) to switch the
   landing page's "no download URL configured yet" note into a real
   **Download StudyUp** button. Until that value is valid the page shows
   the configuration gap explicitly — it never invents a store listing
   link.
   Invitation hand-off without the app: the invite link
   (`https://HOST/i/<code>`) opens the browser page, which shows the
   invitation, a Download button and — when a destination is configured
   — the code appended as `?invite=<code>` so it survives the download.
   Deferred attribution: Android does not hand that code back to the app
   automatically (no install-referrer wiring), so the documented path is
   *reopen the same link after installing* (the App Link then opens the
   app straight onto the invitation) or paste the code in
   Friends → Enter code (kept as fallback).
4. **Verify on two devices**: sign in as A, share invite → B taps link
   (app opens to the accept screen), B signs in (pending token
   resumes), B accepts → both list each other; study on both devices,
   confirm the Community board reflects real totals; test Light/Dark.
5. **Realtime/sweep (optional)**: realtime works out of the box;
   `sweep_stale_presence()` is legacy (rooms UI removed) — safe to
   ignore unless rooms return.

## Privacy notes

- `community_profiles` holds display names/avatar/visibility flags only.
- Raw `study_sessions.segments` are owner-readable only; friends and
  the public board see day aggregates and RPC-computed totals.
- Leaderboard RPCs return opted-in users only (friends scope additionally
  requires an accepted friendship). Clients can never set totals.
- Invite preview exposes only the inviter's display name/avatar.

## D. Feedback Edge Function (`send-feedback`) — deploy + secrets

The Flutter Feedback page calls this function through the existing
Supabase client (`client.functions.invoke('send-feedback', ...)`); the app
never talks to api.resend.com and holds no email secrets.

1. Install the CLI and link your project (one time):
   ```sh
   npm i -g supabase
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   ```
2. Set the three server-side secrets (never in the app, never committed):
   ```sh
   supabase secrets set RESEND_API_KEY=... FEEDBACK_TO_EMAIL=... FEEDBACK_FROM_EMAIL=...
   ```
   `supabase/config.toml` declares the function with `verify_jwt = false`
   on purpose: demo-mode and signed-out users can still send feedback
   (the app explicitly supports anonymous/demo access). Abuse protection
   lives inside the function instead: required gateway `apikey` header,
   strict validation, 16 KB body cap, per-isolate rate limiting
   (5 req / 10 min / IP), fixed server-side recipient.
3. Deploy and test:
   ```sh
   supabase functions deploy send-feedback
   deno test --allow-env supabase/functions/send-feedback/
   ```
4. Resend restrictions: the dev sender `onboarding@resend.dev` may only
   email your own Resend account address, so `FEEDBACK_TO_EMAIL` must be
   that address until you verify a domain; then point
   `FEEDBACK_FROM_EMAIL` at it.
5. Redeploy the function after any code change in
   `supabase/functions/send-feedback/`; secret-only changes need no
   redeploy. A 200 `{ok:true,id}` means Resend queued the mail, not that
   it reached the inbox — verify real delivery by sending one test
   feedback from the app and checking the inbox.
6. **Not-deployed fallback (automatic).** Full chain:
   `FeedbackPage` → `FeedbackSubmitter` → `send-feedback` Edge Function
   → Resend, with the Vercel `api/feedback.js` endpoint as the only
   fallback. When the function is not deployed yet, the Supabase gateway
   answers `404 {"code":"NOT_FOUND","message":"Requested function was
   not found"}`; the app now detects exactly that, keeps the draft, and
   retries the same submission against `FEEDBACK_API_URL` when set,
   otherwise the hosted default
   `https://studyup-4x7z.vercel.app/api/feedback`.
   Real errors a
   deployed transport answered (validation, rate limit, 5xx, timeout)
   are never retried blindly — only the never-seen-by-anyone
   undeployed-function case falls through, so no duplicate email is
   possible. For end-to-end delivery at least one side must be
   deployed: `supabase functions deploy send-feedback` (preferred) or
   `vercel --prod` with `RESEND_API_KEY`, `FEEDBACK_TO_EMAIL` and
   `FEEDBACK_FROM_EMAIL` set in the Vercel project (`api/.env.example`).

## E. Google sign-in branding (why Google shows the Supabase hostname)

The app calls `signInWithOAuth(OAuthProvider.google, redirectTo:
com.studyup.studyup://login-callback/)` (`auth_repository.dart:123`).
supabase_flutter opens the Supabase Auth URL
(`https://<project-ref>.supabase.co/auth/v1/authorize?provider=google`)
in the system browser; Supabase Auth then redirects to Google using the
OAuth client (client ID + secret) stored in Dashboard →
Authentication → Providers → Google.

Two different hosts are involved and only one is cosmetic:

- **Redirect/callback host (infrastructure).** Google returns the user
  to `https://<project-ref>.supabase.co/auth/v1/callback`, and Supabase
  deep-links back to `com.studyup.studyup://login-callback/`, where
  supabase_flutter finishes the sign-in. This is the Supabase Auth
  broker and is correct — changing or removing it breaks sign-in, and
  it cannot be replaced without a custom auth domain
  (Authentication → Custom Domains), which requires owning a DNS domain
  (a `*.vercel.app` host cannot be used for this).
- **Consent/app identity (what you see).** The "to continue to X" line
  inside Google's account chooser is Google-side metadata from the
  Google Cloud project that owns the OAuth client. When the consent
  screen has no App name configured (OAuth Overview → Branding), Google
  falls back to displaying the authorized/redirect domain — which is
  why `<project-ref>.supabase.co` appears instead of the app name. No
  code in this repo can influence that text.

Manual fix (no code change, keeps the working callback): Google Cloud
Console → APIs & Services → OAuth consent screen → Branding → set
**App name = StudyUp**, a user support email, and optionally an app
logo (logos on external/unverified apps require Google verification);
keep `supabase.co` in Authorized domains (the callback host must stay
authorized). Branding changes can take a while to appear and users may
need a fresh consent. Do NOT change `redirectTo`/`authCallbackUrl` or
the intent-filter to chase the displayed text — the flow is already
correct; if Google shows a hostname that does not match your project
ref, that is a dashboard configuration issue in the Google/OAuth
client, not an app bug.
