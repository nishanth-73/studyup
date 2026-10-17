import 'package:flutter/material.dart';

/// Searchable Help guide content for StudyUp.
///
/// Every article describes behaviour verified in the current codebase —
/// real labels, real navigation paths, exact formulas. Anything the app
/// cannot do is stated as missing instead of invented.

class HelpCategory {
  final String id;
  final String title;
  final IconData icon;
  const HelpCategory({
    required this.id,
    required this.title,
    required this.icon,
  });
}

class HelpArticle {
  final String id;
  final String categoryId;
  final String title;
  final List<String> body;
  const HelpArticle({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.body,
  });
}

const helpCategories = [
  HelpCategory(id: 'start', title: 'Getting started', icon: Icons.play_arrow_outlined),
  HelpCategory(id: 'home', title: 'Home & tasks', icon: Icons.home_outlined),
  HelpCategory(id: 'subjects', title: 'Subjects & sources', icon: Icons.book_outlined),
  HelpCategory(id: 'focus', title: 'Focus & sessions', icon: Icons.timer_outlined),
  HelpCategory(id: 'progress', title: 'Progress & goal', icon: Icons.show_chart_outlined),
  HelpCategory(id: 'community', title: 'Community & friends', icon: Icons.people_outline),
  HelpCategory(id: 'notifications', title: 'Notifications', icon: Icons.notifications_outlined),
  HelpCategory(id: 'privacy', title: 'Privacy, data & feedback', icon: Icons.shield_outlined),
];

const helpArticles = [
  HelpArticle(
    id: 'getting-started',
    categoryId: 'start',
    title: 'Getting started',
    body: [
      'When you first open StudyUp you see 3 onboarding slides (Track, Compare, Habit). Swipe through them, then tap Skip or Get Started on the last slide.',
      'Next, Set up your profile: pick an avatar and enter Your name (the name is required — you cannot continue with an empty name), then Continue.',
      'Next, Pick Your Daily Goal: choose 4h to 10h with the chips (8h is the default). This goal drives every ring, bar and percentage in the app. Then continue to the sign-in screen.',
      'The bottom navigation has 4 tabs: Home, Subjects, Progress and Community. Your avatar (top-left on Home) opens Profile, and the bell opens Notifications.',
    ],
  ),
  HelpArticle(
    id: 'account-demo',
    categoryId: 'start',
    title: 'Account, demo access & offline mode',
    body: [
      'If the app was started without backend credentials it shows “Backend not connected — demo access only”. Tapping the demo option signs you in locally on this phone only — nothing is uploaded.',
      'When the backend is connected you can sign up or sign in with email + password, or Continue with Google. After sign-in the app links your local profile and uploads your existing study history exactly once (stable ids, so retries never duplicate anything).',
      'You can also choose an explicit continue-offline option: everything stays on this phone until you sign in.',
      'Signing out (Profile → Privacy & data → Sign out) only clears the saved sign-in on this device. Your local subjects, tasks, sessions and settings stay saved here, and your server account is untouched. Exiting demo mode only ends demo access — it also keeps your data.',
    ],
  ),
  HelpArticle(
    id: 'password-reset',
    categoryId: 'start',
    title: 'Create, reset & change your password',
    body: [
      'Create an account: on the auth screen switch the toggle from Login to Sign Up, enter your email and a password, then tap Sign Up. If email confirmation is on, open the verification email on this phone and tap the link — it reopens StudyUp and finishes sign-up.',
      'Forgot your password? Tap Forgot Password?, enter your email, and open the reset link from the email on this phone. It returns to the app where you enter a new password.',
      'Change your password while signed in: there is no in-app password editor yet — use Forgot Password? with the same email to set a new one.',
      'The reset and verification links only return to the app when Supabase lists com.studyup.studyup://login-callback/ as an allowed redirect (Dashboard → Authentication → URL Configuration). Without it the link opens a browser page instead.',
      'Prefer no password? Use Continue with Google instead — the browser returns to the app automatically.',
    ],
  ),
  HelpArticle(
    id: 'troubleshooting',
    categoryId: 'start',
    title: 'Troubleshooting & empty states',
    body: [
      '“Give your task a title first.” — the task title is required; add one before tapping Schedule Task or Save Changes.',
      '“Choose a PDF/image first.” — for PDF/image sources you must tap Pick and select a file before saving. Closing the picker without a file keeps the sheet open so you can retry.',
      '“That file could not be read” — the picked file was unreadable; try a different file.',
      '“Could not check in / Could not check out” — the session store reported a problem; your existing sessions are untouched. Restarting the app reloads them from this device.',
      'Nothing scheduled yet / No tasks for today — the selected day has no tasks. Use Add Task, or pick another day in the date strip.',
      'No study data yet (Recap) — study at least one checked-in session first.',
      'Community shows demo friends with a DEMO badge and a sign-in banner while offline; sign in to see live data. The quiz bank and the Focus/Plan standalone screens currently have no button or route that opens them from inside the app.',
      'Connection problems: StudyUp is offline-first — tasks, sessions, goals and settings keep saving on this phone without internet. Live Community, friend requests and the leaderboard need a connection (offline they show demo data or a sign-in banner). Feedback sending fails with a clear message while offline and keeps your draft. Finished sessions upload automatically later, and retries never duplicate them because every session has a stable id.',
    ],
  ),
  HelpArticle(
    id: 'home-guide',
    categoryId: 'home',
    title: 'Home: goal card, tasks & mascot',
    body: [
      'The top of Home shows your avatar (tap it to open Profile), your display name (or “StudyUp user”), the date strip for the week, and the bell (opens Notifications; a dot means unread).',
      'Below that, two sliding cards auto-rotate every 8 seconds (swipe to switch): Today’s Goal and Today’s Tasks. Dots under the cards show which one is visible.',
      'Today’s Goal shows a live HH:MM:SS counter of seconds studied today against your daily goal, plus a ring capped at 100% and “Goal reached” once you pass the goal. Studying past the goal keeps counting in the stored total.',
      'Today’s Tasks shows “done of total” for the selected day, or “Nothing scheduled yet” when empty. The Robo mascot beside the cards reacts to your progress.',
      'The greeting (Good morning/afternoon/evening/night) follows the time of day, and the date label shows e.g. “Wed, 14 Oct · Today/Tomorrow/Yesterday”.',
    ],
  ),
  HelpArticle(
    id: 'tasks',
    categoryId: 'home',
    title: 'Tasks: create, edit & reminders',
    body: [
      'Step 1: on Home, pick a day in the date strip (or tap the calendar icon to jump anywhere between year 2000 and 31 Dec 2100). Picking a future day opens the Add sheet automatically.',
      'Step 2: tap Add Task. Enter a title (required), an optional description, and start/end times. Times snap to valid ranges and an end before the start is auto-fixed to start + 60 minutes; durations clamp between 5 minutes and 24 hours.',
      'Step 3: tap Schedule Task (or Save Changes when editing). The task appears under “Today’s Tasks” / “Monday’s Tasks” / “Monday’s Plan” depending on the day.',
      'To complete a task, tick its checkbox (Robo celebrates). To change or remove it, use the task’s Edit / Delete buttons. Deleting also cancels its reminder.',
      'Reminders: a notification fires 5 minutes before a scheduled task when Task reminders are on (Profile → Notifications). Past or already-done tasks never remind. Scheduling uses inexact alarms, so no exact-alarm permission is needed.',
    ],
  ),
  HelpArticle(
    id: 'subjects',
    categoryId: 'subjects',
    title: 'Subjects: add, edit & delete',
    body: [
      'Step 1: open the Subjects tab and tap + (top-right). Enter a name and description, then Add. Empty names become “New Subject”. Every subject starts with one “Chapter 1”. Colours cycle automatically; the icon is always a book.',
      'Step 2: tap a subject card to open it. The ⋮ menu at the top offers Edit (rename), Pin (pins to the top) and Delete.',
      'Delete archives the subject instead of removing it: it disappears from the list but stays in device storage. There is currently no restore or permanent-delete button for archived subjects.',
      'Subject progress is chapter-based: completed chapters ÷ total chapters. A chapter only counts when it has topics and all of them are done.',
    ],
  ),
  HelpArticle(
    id: 'chapters-topics',
    categoryId: 'subjects',
    title: 'Chapters & topics',
    body: [
      'Inside a subject, tap Add to create a chapter (empty titles become “New Chapter”). Tap a chapter to expand it and see its topics.',
      'Each chapter’s ⋮ menu offers Rename, Add sources and Delete. Renaming with an empty name does nothing (the old name is kept).',
      'Inside an expanded chapter, type in “Add a topic…” to add one (empty adds are ignored). Tap a topic to toggle it done; the topic’s ⋮ menu offers Edit and Delete (empty edits are ignored).',
      'A chapter counts as complete only when it has at least one topic and every topic is done.',
    ],
  ),
  HelpArticle(
    id: 'sources',
    categoryId: 'subjects',
    title: 'Sources: links, PDFs & images',
    body: [
      'Sources belong to a chapter (not to a subject or topic). Open a subject, expand a chapter, then use the chapter’s ⋮ menu → Add sources.',
      'Three kinds are supported: Link, PDF and Image. Pick the kind with the chips at the top of the sheet.',
      'Link: paste a URL and save. addresses without a scheme open with https:// added.',
      'PDF: tap Pick, choose a .pdf file. Image: tap Pick, choose from the gallery. Then Save. The file is copied into the app’s private files folder first — the original picker path is never stored.',
      'Tap a source row to open it: images show in a dialog, PDFs open in your PDF app, links open in the browser. Use the source’s delete button to remove it. Sources cannot be edited — delete and re-add instead.',
    ],
  ),
  HelpArticle(
    id: 'focus-sessions',
    categoryId: 'focus',
    title: 'Focus sessions',
    body: [
      'Step 1: open the Progress tab. In the Today’s Session card tap Check In to start studying. The timer ticks (HH:MM:SS) while checked in and freezes while checked out.',
      'Step 2: tap Check Out to pause. Checking out banks the studied time into that calendar day — even across midnight, each date keeps exactly the minutes studied on it. Tap Check In again to resume the same session.',
      'While checked out the card shows “Paused · daily session”; with nothing started it says “Tap Check In to begin today’s session”.',
      'How time is counted: studied time is the sum of the session’s time segments (pause-aware), split at local midnight per date. A paused session left overnight is closed exactly at its pause time, preserving what you banked; only running time after midnight counts for the new day.',
      'All day boundaries use your phone’s local time. Only finished sessions upload to the server; the active (unchecked-out) session never syncs until you check out.',
    ],
  ),
  HelpArticle(
    id: 'daily-goal',
    categoryId: 'progress',
    title: 'Daily goal',
    body: [
      'Your goal is chosen once during setup (4h–10h, default 8h = 480 minutes). Privacy & data shows the current value as “Daily goal: Xm”. There is currently no in-app editor to change the goal afterwards.',
      'Progress % = minutes studied today ÷ goal. Rings, weekly bars and the Focus ring cap the display at 100%, but the stored minutes keep the real total including overflow.',
      'Below 100% you see the remaining share; at or above 100% the day shows “Goal reached” and Robo celebrates (once per day). A goal of 0 or less never counts as reached.',
      'The day resets at local midnight. Streaks and charts use the same local-day boundary.',
    ],
  ),
  HelpArticle(
    id: 'streaks-levels',
    categoryId: 'progress',
    title: 'Streaks, levels & charts',
    body: [
      'A day counts when real study time is recorded. The current streak is the run of consecutive studied days ending today (if today is still quiet, yesterday is used as the anchor); the best streak is the longest such run since your first study day.',
      'Levels come from total minutes: 1 minute earns 1 XP. Level N needs 60 × N × (N−1) ÷ 2 XP total (Level 1: 0, Level 2: 60, Level 3: 180, …). The bar shows progress into the next level.',
      'Weekly card: Monday–Sunday bars, each day capped at 100% of the goal, with exact minutes + 2-decimal % in tooltips. Monthly card: per-week totals plus a line of average % of daily goal. The day-part pie splits the day into Morning 6–12, Afternoon 12–18, Evening 18–24, Night 0–6 as % of the shared goal.',
      'Compare pickers: the date picker never allows future days; weeks and months are chosen with dedicated dialogs. The calendar marks studied days, empty ended days, and greys out days before your first launch.',
    ],
  ),
  HelpArticle(
    id: 'community',
    categoryId: 'community',
    title: 'Community: invites, friends & leaderboard',
    body: [
      'While signed out, Community runs on this device with demo friends (badged DEMO) plus a sign-in banner. Sign in to switch to live server data — demo entries are never mixed into live boards.',
      'Server invites: tap Share/Invite in Community to create a 7-day link (only its hash is stored server-side) and send it. The recipient opens it in StudyUp, previews your name/avatar, signs in if needed (the token waits for them), then taps Accept invitation. Expired, revoked, used or self-invites show a clear reason.',
      'Offline invite codes: Friends → Enter code accepts SUP1- codes (uppercase-hex, valid 30 days) generated on-device with your live week totals.',
      'Friends: Find friends searches opted-in users by display name. Send a request, Accept/Decline incoming ones (arrive in realtime), or Remove/Block/Report from a friend’s menu. Blocking hides them immediately; reports queue on this device. Only display names are ever shown — never emails or contact details.',
      'Leaderboard: you appear only if leaderboard sharing is on (Friends → Privacy toggles). Your friends board covers accepted friends only and is computed server-side for Monday–Sunday weeks; ties share a rank (1, 2, 2, 4). Days with no shared data say so instead of showing zero.',
      'Sync limits: only finished (checked-out) sessions upload, with stable ids so retries never duplicate. The in-progress session stays on this phone until you check out.',
    ],
  ),
  HelpArticle(
    id: 'notifications-help',
    categoryId: 'notifications',
    title: 'Notifications',
    body: [
      'Profile → Notifications has 3 switches: Task reminders (5 minutes before scheduled tasks), Live progress (ongoing timer while you study) and Daily goal reached (once per day when the goal is met).',
      'If system notifications are off, the page says so with an Open settings button — the in-app switches cannot show anything until you enable them in system settings.',
      'The bell on Home opens the Notification centre: live progress (derived, never stored), Upcoming reminders sorted by date, and Goal reached history. Opening the centre marks everything read and clears the dot.',
      'Turning Task reminders back on re-schedules every valid upcoming reminder; turning them off cancels pending task reminders immediately without touching the goal alert.',
    ],
  ),
  HelpArticle(
    id: 'privacy-help',
    categoryId: 'privacy',
    title: 'Privacy, data & erase',
    body: [
      'Profile → Privacy & data → Your stored data shows live counts plus three notes: what lives on this device (plain app data, not encrypted — profile, subjects, tasks, sessions, goal, notification history, quiz bests, community data, feedback drafts, settings, plus downloaded files in the app’s private folder); what lives on Supabase while signed in (community profile, friend requests/friendships, invitation hashes, ended sessions with per-day totals — only you can read/change your rows); and what syncs (ended sessions upload with duplicate-proof ids; everything else stays on-device).',
      'Sign out clears only the saved sign-in; local records stay. Exit demo only ends demo access; it also keeps your data.',
      'Erase all local data asks for confirmation first (“Erase all local data?” with Cancel and Erase everything, warning it cannot be undone). It cancels scheduled reminders and the live timer, deletes downloaded files, wipes the app’s stored records and resets the screens. It never deletes your Supabase account or server records — only their local copies. The saved sign-in is cleared, so you sign in again afterwards. Temporary image caches are left for Android to clean.',
    ],
  ),
  HelpArticle(
    id: 'feedback-help',
    categoryId: 'privacy',
    title: 'Feedback & support',
    body: [
      'Profile → Feedback sends a message to the StudyUp inbox. Pick a Category (Bug report, Feature request, Improvement, Other), add a Subject (3–120 characters) and a Message (10–2000 characters). Contact email is optional — leave it empty if you don’t want a reply.',
      'Only the fields on the form plus the app version/platform are sent — nothing else from your device. Tapping Send feedback shows Sending… and ignores extra taps.',
      'On success you see a confirmation and the form resets. On any failure (no connection, timeout, server error, or sending not set up in your build) you get an actionable message and your draft is kept — on screen and on this device — so you can retry.',
      'Sending prefers the secure Supabase server whenever the backend is configured, and falls back to the backup endpoint when only its URL is set. Either way, success means the mail server accepted the message for queuing — inbox delivery itself is handled by the email provider.',
      'A human reads the inbox. A reply is only possible if you left a contact email, and replies can take a few days — there is no live chat or phone support. If you left no email, your report is still read and used to fix the app.',
    ],
  ),
  HelpArticle(
    id: 'payments',
    categoryId: 'privacy',
    title: 'Payments & subscriptions',
    body: [
      'StudyUp currently has no subscriptions, in-app purchases or ads, and it collects no payment details anywhere. There is nothing to update and no billing settings to manage.',
      'Study tracking, goals, reminders, Community and feedback are all available without any purchase, so a “payment settings” screen simply does not exist in this app.',
    ],
  ),
];

/// Case-insensitive search over titles + body. Empty query returns all.
List<HelpArticle> searchHelpArticles(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return helpArticles;
  return helpArticles
      .where(
        (a) =>
            a.title.toLowerCase().contains(q) ||
            a.body.any((p) => p.toLowerCase().contains(q)),
      )
      .toList();
}

List<HelpArticle> helpArticlesIn(String categoryId) =>
    helpArticles.where((a) => a.categoryId == categoryId).toList();
