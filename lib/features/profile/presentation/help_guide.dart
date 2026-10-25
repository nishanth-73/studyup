import 'package:flutter/material.dart';

/// Compact Help content for StudyUp: expandable how-to topics.
///
/// Every line describes behaviour verified in the current codebase — real
/// labels, real controls, real navigation. Anything the app cannot do is
/// left out instead of invented.

/// Optional structured section with a heading and bullet points.
class HelpSection {
  final String heading;
  final List<String> lines;
  const HelpSection({
    required this.heading,
    required this.lines,
  });
}

/// One expandable help topic shown as a compact row on the Help page.
class HelpTopic {
  final String id;
  final String title;
  final IconData icon;

  /// Short, action-first lines; each answers a real user question.
  final List<String> lines;

  /// Optional structured sections with headings (for FAQs and topic guides).
  final List<HelpSection> sections;

  const HelpTopic({
    required this.id,
    required this.title,
    required this.icon,
    required this.lines,
    this.sections = const [],
  });
}

const List<HelpTopic> helpTopics = [
  HelpTopic(
    id: 'home',
    title: 'Home',
    icon: Icons.home_outlined,
    lines: [
      'Pick a day in the date strip, or tap the calendar icon to jump to any date.',
      'Tap Add Task, give it a title, set the times, then tap Schedule Task.',
      'Tick the circle on a task to mark it done; Edit and Delete sit on the task row.',
      'A reminder fires 5 minutes before a task starts while Task reminders are on.',
    ],
  ),
  HelpTopic(
    id: 'subjects',
    title: 'Subjects',
    icon: Icons.book_outlined,
    lines: [
      'Tap + on Subjects, enter a name and description, then tap Add.',
      'Open a subject and tap Add to create a chapter; tap a chapter to expand it.',
      'Type in “Add a topic…” to add topics; tap a topic to mark it done.',
      'The ⋮ menus rename or delete chapters and topics, pin a subject, and add sources.',
    ],
  ),
  HelpTopic(
    id: 'focus',
    title: 'Focus & sessions',
    icon: Icons.timer_outlined,
    lines: [
      'Open the Progress tab and tap Check In to start today’s session.',
      'The timer keeps counting wherever you go in the app, and Home shows it live.',
      'Tap Check Out to pause; your studied time is banked and stays saved.',
      'Tap Check In again to resume. Time is kept per calendar day, so a session left paused ends with the day.',
    ],
  ),
  HelpTopic(
    id: 'progress',
    title: 'Progress',
    icon: Icons.show_chart_outlined,
    lines: [
      'The Progress tab shows your real study time: today’s session, the weekly and monthly charts, and the calendar.',
      'Bars and rings compare each day with your daily goal; studying past the goal keeps counting.',
      'The day-parts pie shows when you study, from morning to night.',
      'Use the Proxy / Insights switch at the top to flip between the two views.',
    ],
  ),
  HelpTopic(
    id: 'community',
    title: 'Community',
    icon: Icons.people_outline_rounded,
    sections: [
      HelpSection(
        heading: 'Inviting friends & joining circles',
        lines: [
          'Tap \'Invite Friends\' at the bottom of Community to share your personal invite link.',
          'When a friend opens your link, they can tap Accept Invitation to connect study circles.',
          'If signed out, sign in first; your pending invite is saved and accepted after login.',
          'On the web invite page, the Download button shows “Coming soon” until the APK is available.',
        ],
      ),
      HelpSection(
        heading: 'Podium, rankings & member progress',
        lines: [
          'The Top 3 Podium celebrates the week\'s top learners (#1 in green) with their profile avatars.',
          'Weekly totals reflect actual completed study sessions from Monday to Sunday, matching Insights.',
          'The Leaderboard ranks members by weekly study hours; your entry is highlighted with a YOU badge.',
          'Tap \'See all\' to view the full leaderboard with rankings, streaks, and progress bars.',
          'Tap any member on the podium or leaderboard to inspect their 7-day study time and sessions.',
        ],
      ),
      HelpSection(
        heading: 'Troubleshooting & FAQs',
        lines: [
          'Missing minutes? Ensure your session was ended and saved in the Focus tab before checking Community.',
          'Stats not updating? Pull down to refresh Community, or tap Retry on the network banner.',
          'Broken or expired link? Ask your friend to tap \'Invite Friends\' again to share a fresh link.',
          'Already connected? You cannot accept your own link or re-add an existing study friend.',
        ],
      ),
    ],
    lines: [
      'Tap \'Invite Friends\' at the bottom of Community to share your personal invite link.',
      'When a friend opens your link, they can tap Accept Invitation to connect study circles.',
      'If signed out, sign in first; your pending invite is saved and accepted after login.',
      'On the web invite page, the Download button shows “Coming soon” until the APK is available.',
      'The Top 3 Podium celebrates the week\'s top learners (#1 in green) with their profile avatars.',
      'Weekly totals reflect actual completed study sessions from Monday to Sunday, matching Insights.',
      'The Leaderboard ranks members by weekly study hours; your entry is highlighted with a YOU badge.',
      'Tap \'See all\' to view the full leaderboard with rankings, streaks, and progress bars.',
      'Tap any member on the podium or leaderboard to inspect their 7-day study time and sessions.',
      'Missing minutes? Ensure your session was ended and saved in the Focus tab before checking Community.',
      'Stats not updating? Pull down to refresh Community, or tap Retry on the network banner.',
      'Broken or expired link? Ask your friend to tap \'Invite Friends\' again to share a fresh link.',
      'Already connected? You cannot accept your own link or re-add an existing study friend.',
    ],
  ),
];
