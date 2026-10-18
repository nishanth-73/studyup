import 'package:flutter/material.dart';

/// Compact Help content for StudyUp: four expandable how-to topics only.
///
/// Every line describes behaviour verified in the current codebase — real
/// labels, real controls, real navigation. Anything the app cannot do is
/// left out instead of invented.

/// One expandable help topic shown as a compact row on the Help page.
class HelpTopic {
  final String id;
  final String title;
  final IconData icon;

  /// Short, action-first lines; each answers a real user question.
  final List<String> lines;
  const HelpTopic({
    required this.id,
    required this.title,
    required this.icon,
    required this.lines,
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
];
