import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../../../progress/presentation/study_progress_controller.dart';
import '../../data/home_models.dart';
import '../home_controller.dart';

String _formatHms(Duration e) {
  final h = e.inHours.toString().padLeft(2, '0');
  final m = (e.inMinutes % 60).toString().padLeft(2, '0');
  final s = (e.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// Seconds-accurate study total for one calendar date (midnight to
/// midnight). Summing [secondsInRange] keeps the live timer exact while
/// the stored minutes stay untouched. Overflow past the goal is
/// preserved (only the ring visual is capped).
int _secondsForDate(StudyProgressState progress, DateTime day, DateTime now) {
  final start = DateTime(day.year, day.month, day.day);
  final end = start.add(const Duration(days: 1));
  var seconds = 0;
  for (final session in progress.sessions) {
    seconds += session.secondsInRange(start, end, now);
  }
  return seconds;
}

const TextStyle _cardTitle = TextStyle(
  color: Colors.white,
  fontSize: 22,
  height: 1.1,
  fontWeight: FontWeight.w800,
);

const TextStyle _cardTimer = TextStyle(
  color: Colors.white,
  fontSize: 26,
  height: 1.15,
  fontWeight: FontWeight.w800,
  fontFeatures: [FontFeature.tabularFigures()],
);

const TextStyle _cardCount = TextStyle(
  color: Colors.white,
  fontSize: 30,
  height: 1.15,
  fontWeight: FontWeight.w800,
  fontFeatures: [FontFeature.tabularFigures()],
);

const TextStyle _cardSub = TextStyle(
  color: Colors.white70,
  fontSize: 11,
  fontWeight: FontWeight.w600,
);

/// Two-slide live hero: Today's Goal (alarm-clock art) and Today's Tasks
/// (checklist art). Artwork comes from the bundled slide illustrations;
/// every text, timer, ring, and count is a live Flutter widget fed by the
/// existing study/task providers. Auto-slide, dots, swipe, and the
/// live/frozen session wiring are preserved.
class HomeSlidingCards extends ConsumerStatefulWidget {
  final DateTime selectedDate;
  const HomeSlidingCards({super.key, required this.selectedDate});

  @override
  ConsumerState<HomeSlidingCards> createState() => _HomeSlidingCardsState();
}

class _HomeSlidingCardsState extends ConsumerState<HomeSlidingCards> {
  final _pages = PageController();
  Timer? _autoSlide;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    // Auto-slide every 8s; manual swipe still works and just re-bases it.
    _autoSlide = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      final next = (_page + 1) % 2;
      _pages.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _autoSlide?.cancel();
    _pages.dispose();
    super.dispose();
  }

  DateTime get selectedDate => widget.selectedDate;

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(studyProgressProvider);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sel = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final isToday = sel.isAtSameMomentAs(today);

    // Slide 1 always shows TODAY's accumulated study time
    // (seconds-accurate) against the shared daily goal.
    final todaySeconds = _secondsForDate(progress, today, now);
    final goalMinutes = progress.dailyStudyGoalMinutes;
    final goalSeconds = goalMinutes * 60;
    final ringValue = goalSeconds <= 0
        ? 0.0
        : (todaySeconds / goalSeconds).clamp(0.0, 1.0);

    final home = ref.watch(homeControllerProvider);
    final selKey = dateKey(sel);
    final dayTasks = home.tasksByDate[selKey] ?? const <StudyTask>[];
    final tasksDone = dayTasks.where((t) => t.isDone).length;
    final tasksTotal = dayTasks.length;
    final tasksTitle = isToday
        ? "Today's Tasks"
        : "${weekdayFull[sel.weekday - 1]}'s Tasks";
    final tasksSub = tasksTotal == 0
        ? 'Nothing scheduled yet'
        : '$tasksDone of $tasksTotal done';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              SizedBox(
                // Fixed slide viewport; the artwork spans the full card
                // height edge to edge with the dots floating over it.
                height: 170,
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    _ArtSlide(
                      art: 'assets/images/slide_goal_art.png',
                      content: _GoalContent(
                        todaySeconds: todaySeconds,
                        goalMinutes: goalMinutes,
                        ringValue: ringValue,
                      ),
                    ),
                    _ArtSlide(
                      art: 'assets/images/slide_tasks_art.png',
                      content: _TasksContent(
                        title: tasksTitle,
                        done: tasksDone,
                        total: tasksTotal,
                        sub: tasksSub,
                      ),
                    ),
                  ],
                ),
              ),
              // Page dots float over the artwork near the bottom, centered.
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(2, (i) {
                    final selected = i == _page;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: selected ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : Colors.white54,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        if (progress.error != null) ...[
          const SizedBox(height: 8),
          Text(
            'Study data issue: ${progress.error}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// One slide: bundled illustration as a full-bleed background with a dark
/// left scrim so the live [content] widgets stay readable.
class _ArtSlide extends StatelessWidget {
  final String art;
  final Widget content;
  const _ArtSlide({required this.art, required this.content});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(art, fit: BoxFit.cover, alignment: Alignment.center),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.black.withValues(alpha: 0.82),
                Colors.black.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.15),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: content,
        ),
      ],
    );
  }
}

/// Slide 1 live content: real accumulated study time, real goal progress.
class _GoalContent extends StatelessWidget {
  final int todaySeconds;
  final int goalMinutes;
  final double ringValue;
  const _GoalContent({
    required this.todaySeconds,
    required this.goalMinutes,
    required this.ringValue,
  });

  @override
  Widget build(BuildContext context) {
    final reached = goalMinutes > 0 && todaySeconds >= goalMinutes * 60;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Today's",
                  style: _cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  'Goal',
                  style: _cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  _formatHms(Duration(seconds: todaySeconds)),
                  style: _cardTimer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  reached ? 'Goal reached' : 'Goal ${_fmtGoal(goalMinutes)}',
                  style: _cardSub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          key: const ValueKey('home-today-goal-ring-container'),
          width: 92,
          height: 92,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: CircularProgressIndicator(
                  key: const ValueKey('home-today-goal-ring'),
                  value: ringValue,
                  strokeWidth: 7,
                  backgroundColor: Colors.white38,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              Text(
                '${(ringValue * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Slide 2 live content: real completed/total task count.
class _TasksContent extends StatelessWidget {
  final String title;
  final int done;
  final int total;
  final String sub;
  const _TasksContent({
    required this.title,
    required this.done,
    required this.total,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    // Split "Today's Tasks" -> ("Today's", "Tasks") so both slides share
    // the two-line title composition ("Monday's", "Tasks" off-today).
    final parts = title.split(' ');
    final line1 = parts.length > 1
        ? parts.sublist(0, parts.length - 1).join(' ')
        : title;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  line1,
                  style: _cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  'Tasks',
                  style: _cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  sub,
                  style: _cardSub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          '$done/$total',
          style: _cardCount,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

String _fmtGoal(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final r = minutes % 60;
  return r == 0 ? '${h}h' : '${h}h ${r}m';
}
