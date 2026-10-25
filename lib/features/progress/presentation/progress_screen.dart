import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/week_picker_dialog.dart';
import '../../../core/widgets/weekly_study_time_card.dart';
import '../../../core/widgets/date_picker_sheet.dart';
import '../data/study_session.dart';
import '../data/study_day.dart';
import '../data/app_metadata.dart';
import '../data/study_gamification.dart';
import 'study_progress_controller.dart';
import 'streak_level_summary.dart';

String _fmtDur(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final r = minutes % 60;
  return r == 0 ? '${h}h' : '${h}h ${r}m';
}

String _dkey(DateTime d) => '${d.year}-${d.month}-${d.day}';

DateTime _monday(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

int _trackedSecondsForDate(
  List<StudySession> sessions,
  DateTime date,
  DateTime now,
) {
  final start = DateTime(date.year, date.month, date.day);
  final end = start.add(const Duration(days: 1));
  return sessions.fold(
    0,
    (seconds, session) => seconds + session.secondsInRange(start, end, now),
  );
}

double _cappedGoalProgress(int trackedSeconds, int goalMinutes) {
  final goalSeconds = goalMinutes * 60;
  if (goalSeconds <= 0) return 0;
  return (trackedSeconds / goalSeconds).clamp(0.0, 1.0);
}

class _TodayGoalProgressRing extends StatefulWidget {
  final int trackedSeconds;
  final int goalMinutes;
  final DateTime selectedDate;
  final List<StudySession> sessionsRevision;
  final double size;

  const _TodayGoalProgressRing({
    required this.trackedSeconds,
    required this.goalMinutes,
    required this.selectedDate,
    required this.sessionsRevision,
    required this.size,
  });

  @override
  State<_TodayGoalProgressRing> createState() => _TodayGoalProgressRingState();
}

class _TodayGoalProgressRingState extends State<_TodayGoalProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..forward();
  }

  @override
  void didUpdateWidget(_TodayGoalProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dateChanged =
        oldWidget.selectedDate.year != widget.selectedDate.year ||
        oldWidget.selectedDate.month != widget.selectedDate.month ||
        oldWidget.selectedDate.day != widget.selectedDate.day;
    if (dateChanged ||
        oldWidget.goalMinutes != widget.goalMinutes ||
        !identical(oldWidget.sessionsRevision, widget.sessionsRevision)) {
      _entrance.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _cappedGoalProgress(
      widget.trackedSeconds,
      widget.goalMinutes,
    );
    return SizedBox(
      key: const ValueKey('today-session-goal-ring-container'),
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _entrance,
        builder: (context, _) {
          final visibleProgress = progress * _entrance.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                key: const ValueKey('today-session-goal-ring'),
                width: widget.size,
                height: widget.size,
                child: CircularProgressIndicator(
                  value: visibleProgress,
                  strokeWidth: 10,
                  backgroundColor: AppColors.track,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.cta,
                  ),
                ),
              ),
              Text(
                '${(visibleProgress * 100).round()}%',
                style: AppTextStyles.section18.copyWith(fontSize: 22),
                semanticsLabel:
                    '${(progress * 100).round()} percent of daily goal',
              ),
            ],
          );
        },
      ),
    );
  }
}

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});
  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  int _tab = 0; // 0 = Proxy, 1 = Insights
  final GlobalKey _monthlyChartCardKey = GlobalKey();
  bool _monthlyChartVisible = false;
  bool _visibilityCheckScheduled = false;

  late DateTime _today;
  late DateTime _weeklyChartDate;
  late DateTime _monthlyChartDate;
  DateTime? _weeklyCompareDate;
  DateTime? _monthlyCompareDate;
  DateTime? _pieCompareDate;

  /// Watches for calendar-day rollover (midnight, device clock changes):
  /// daily totals derive from the date on every build, and this refreshes
  /// [_today] so a long-open screen switches to the new date from zero
  /// without touching history or running sessions.
  Timer? _dayWatch;

  // Check-in/out logic state.

  // Calendar view state (any month accessible).
  late int _viewYear;
  late int _viewMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _viewYear = _today.year;
    _viewMonth = _today.month;
    _weeklyChartDate = _today;
    _monthlyChartDate = _today;
    _dayWatch = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final current = DateTime.now();
      final day = DateTime(current.year, current.month, current.day);
      if (day != _today) setState(() => _today = day);
    });
    _scheduleMonthlyVisibilityCheck();
  }

  @override
  void dispose() {
    _dayWatch?.cancel();
    super.dispose();
  }

  void _scheduleMonthlyVisibilityCheck() {
    if (_visibilityCheckScheduled) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted || _tab != 1) return;
      final cardContext = _monthlyChartCardKey.currentContext;
      if (cardContext == null) {
        if (_monthlyChartVisible) {
          setState(() => _monthlyChartVisible = false);
        }
        return;
      }
      final card = cardContext.findRenderObject();
      final viewport = cardContext
          .findAncestorRenderObjectOfType<RenderAbstractViewport>();
      if (card is! RenderBox || !card.hasSize || viewport == null) {
        return;
      }

      final cardRect = card.localToGlobal(Offset.zero) & card.size;
      final viewportRect = MatrixUtils.transformRect(
        viewport.getTransformTo(null),
        viewport.paintBounds,
      );
      final visibleHeight =
          (cardRect.bottom < viewportRect.bottom
              ? cardRect.bottom
              : viewportRect.bottom) -
          (cardRect.top > viewportRect.top ? cardRect.top : viewportRect.top);
      final threshold = _monthlyChartVisible ? 8.0 : 48.0;
      final visible = visibleHeight >= threshold;
      if (visible == _monthlyChartVisible) return;
      setState(() {
        _monthlyChartVisible = visible;
      });
    });
  }

  DateTime? _firstLaunchDay() {
    final meta = ref.read(appMetadataProvider).valueOrNull;
    if (meta == null) return null;
    final f = meta.firstLaunchDay;
    return DateTime(f.year, f.month, f.day);
  }

  bool _disabled(DateTime day) {
    final f = _firstLaunchDay();
    if (f == null) return false;
    final d = DateTime(day.year, day.month, day.day);
    return d.isBefore(f);
  }

  bool _present(DateTime day) {
    if (_disabled(day)) return false;
    if (day.isAfter(_today)) return false;
    return ref.read(studyProgressProvider).minutesForDate(day) > 0;
  }

  bool _absent(DateTime day) {
    if (_disabled(day)) return false;
    if (day.isAfter(_today)) return false;
    final d = DateTime(day.year, day.month, day.day);
    if (d.isAtSameMomentAs(_today)) return false;
    return ref.read(studyProgressProvider).minutesForDate(day) == 0;
  }

  String _elapsedLabel(Duration elapsed) {
    final hours = elapsed.inHours.toString().padLeft(2, '0');
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      currentIndex: 2,
      body: SafeArea(
        bottom: false,
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _scheduleMonthlyVisibilityCheck();
            return false;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            children: [
              Text('Your Progress', style: AppTextStyles.title30),
              Text(
                'Small steps. Big results.',
                style: AppTextStyles.secondary14,
              ),
              const SizedBox(height: 14),
              // Proxy | Insights switch.
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  children: [
                    _seg(context, 0, 'Proxy'),
                    _seg(context, 1, 'Insights'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (ref.watch(studyProgressProvider).error != null)
                Text(
                  'Study data could not be loaded: ${ref.watch(studyProgressProvider).error}',
                  style: const TextStyle(color: AppColors.error),
                ),
              if (_tab == 0)
                ..._proxyBody(ref.watch(studyProgressProvider))
              else
                ..._insightsBody(),
              // Scroll clearance above the floating nav (AppShell math).
              SizedBox(height: AppShell.scrollClearance(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seg(BuildContext context, int i, String label) {
    final sel = _tab == i;
    return Expanded(
      child: Material(
        color: sel ? AppColors.cta : Colors.transparent,
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          borderRadius: BorderRadius.circular(100),
          splashColor: AppColors.primary.withValues(alpha: 0.3),
          onTap: () {
            SystemSound.play(SystemSoundType.click);
            HapticFeedback.selectionClick();
            setState(() {
              _tab = i;
              if (i != 1) _monthlyChartVisible = false;
            });
            _scheduleMonthlyVisibilityCheck();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Text(
                label,
                style: AppTextStyles.caption13.copyWith(
                  color: sel ? AppColors.onCta : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- PROXY ----------------
  // The daily goal is managed from Profile/Settings.
  // Progress circle follows chosen daily goal.

  /// CHECK IN entry on this card: starts a new session when none is
  /// active, resumes the paused session otherwise, and never duplicates a
  /// running session.
  Future<void> _checkIn() async {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
    try {
      await ref.read(studyProgressProvider.notifier).checkIn();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not check in: $error')));
      }
    }
  }

  /// CHECK OUT entry on this card: pauses the running session immediately.
  /// A paused or absent session is a safe no-op.
  Future<void> _checkOut() async {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
    try {
      await ref.read(studyProgressProvider.notifier).checkOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not check out: $error')));
      }
    }
  }

  List<Widget> _proxyBody(StudyProgressState progress) {
    final activeSession = progress.activeSession;
    // Calendar-date accumulation (midnight to midnight): sessions simply
    // add up within the date; overflow past the goal is preserved exactly.
    final now = DateTime.now();
    final dayStart = DateTime(_today.year, _today.month, _today.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final completed = progress.minutesForDate(_today, now: now);
    final goalMinutes = progress.dailyStudyGoalMinutes;
    final trackedSeconds = _trackedSecondsForDate(
      progress.sessions,
      _today,
      now,
    );
    final checkedIn = activeSession != null;
    final isPaused = activeSession?.isPaused ?? false;
    final running = checkedIn && !isPaused;
    StudySession? latestTodaySession;
    for (final session in progress.sessions) {
      final sessionEnd = session.checkOutTime ?? now;
      final overlaps =
          sessionEnd.isAfter(dayStart) && session.checkInTime.isBefore(dayEnd);
      if (overlaps &&
          (latestTodaySession == null ||
              session.checkInTime.isAfter(latestTodaySession.checkInTime))) {
        latestTodaySession = session;
      }
    }
    final checkIn =
        activeSession?.checkInTime ?? latestTodaySession?.checkInTime;
    final checkOut = latestTodaySession?.checkOutTime;

    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's Session", style: AppTextStyles.section18),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    key: const ValueKey('today-session-details'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Goal: ${_fmtDur(goalMinutes)}',
                        style: AppTextStyles.body14Bold,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      if (isGoalReached(completed, goalMinutes))
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Pill(
                            "Today's Goal Reached",
                            background: AppColors.green,
                            foreground: AppColors.onCta,
                          ),
                        ),
                      Text(
                        activeSession == null
                            ? 'No active session'
                            : isPaused
                            ? 'Paused · daily session'
                            : 'Studying · daily session',
                        style: AppTextStyles.caption12,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _elapsedLabel(
                          activeSession?.durationAt(now) ?? Duration.zero,
                        ),
                        style: AppTextStyles.title28.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (checkIn != null || checkOut != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Check-in: ${checkIn == null ? '—' : TimeOfDay.fromDateTime(checkIn).format(context)}\n'
                            'Check-out: ${checkOut == null ? '—' : TimeOfDay.fromDateTime(checkOut).format(context)}',
                            style: AppTextStyles.caption12,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _TodayGoalProgressRing(
                    trackedSeconds: trackedSeconds,
                    goalMinutes: goalMinutes,
                    selectedDate: _today,
                    sessionsRevision: progress.sessions,
                    size: MediaQuery.sizeOf(context).width < 360 ? 88 : 100,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _CheckInOutButtons(
              checkInEnabled:
                  progress.isLoaded &&
                  progress.error == null &&
                  (!checkedIn || isPaused),
              checkOutEnabled:
                  progress.isLoaded && progress.error == null && running,
              onCheckIn: _checkIn,
              onCheckOut: _checkOut,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _DaypartPieCard(
        minutesByPart: progress.dayPartMinutes(_today, now: now),
        comparisonDate: _pieCompareDate,
        comparisonMinutesByPart: _pieCompareDate == null
            ? null
            : progress.dayPartMinutes(_pieCompareDate!),
        goalMinutes: goalMinutes,
        onCompare: _togglePieCompare,
      ),
      const SizedBox(height: 16),
      const StreakLevelRow(),
    ];
  }

  // ---------------- INSIGHTS ----------------
  List<Widget> _insightsBody() {
    return [
      // Compact calendar: tight padding/gaps, small cells.
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month/year caption. Months change by swiping the grid.
            Row(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      '${_monthName(_viewMonth)} $_viewYear',
                      style: AppTextStyles.section18.copyWith(fontSize: 22),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Dow('M'),
                _Dow('T'),
                _Dow('W'),
                _Dow('T'),
                _Dow('F'),
                _Dow('S'),
                _Dow('S'),
              ],
            ),
            const SizedBox(height: 2),
            _monthGrid(),
            const SizedBox(height: 6),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: AppColors.green, label: 'Present'),
                SizedBox(width: 16),
                _LegendDot(color: Colors.redAccent, label: 'Absent'),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _weeklyStudyTimeCard(),
      const SizedBox(height: 16),
      _monthlyStudyTimeCard(),
    ];
  }

  List<int> _minutesForWeek(DateTime date) {
    return ref.read(studyProgressProvider).minutesByWeekday(date);
  }

  /// Monday actually charted: the selected week's Monday when it belongs
  /// to the viewed month, else the current week (if viewed) or W1.
  DateTime _effectiveWeekMonday(List<MonthWeekRow> rows) {
    final selected = _monday(_weeklyChartDate);
    for (final row in rows) {
      if (row.monday.isAtSameMomentAs(selected)) return selected;
    }
    final now = DateTime.now();
    if (now.year == _viewYear && now.month == _viewMonth) {
      return _monday(now);
    }
    return rows.first.monday;
  }

  /// Keep the charted week inside the newly viewed month.
  void _snapWeeklySelection() {
    final rows = monthWeekRows(_viewYear, _viewMonth);
    final effective = _effectiveWeekMonday(rows);
    if (!effective.isAtSameMomentAs(_monday(_weeklyChartDate))) {
      _weeklyChartDate = effective;
    }
  }

  List<int> _minutesForMonthWeeks(DateTime date) {
    return ref.read(studyProgressProvider).minutesByMonthWeek(date);
  }

  /// Compare-day picker: the shared bottom-sheet calendar. Past dates and
  /// today are selectable; future dates are disabled in the grid AND
  /// rejected in the update logic, and the ceiling follows the device's
  /// current local date (no UTC tricks).
  Future<DateTime?> _showCompareDatePicker({
    required DateTime initialDate,
    required String helpText,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var initial = DateTime(
      initialDate.year,
      initialDate.month,
      initialDate.day,
    );
    if (initial.isAfter(today)) initial = today;
    return showCalendarPickerSheet(
      context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: today,
      title: helpText,
    );
  }

  /// Weekly Compare toggle: the single entry point for week selection.
  /// No compare -> open the weeks popup (W1..Wn of the viewed month,
  /// past and present weeks only); compare set -> clear it.
  Future<void> _toggleWeeklyCompare() async {
    if (_weeklyCompareDate != null) {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.selectionClick();
      setState(() => _weeklyCompareDate = null);
      return;
    }
    final picked = await _showWeekCompareDialog();
    if (picked == null || !mounted) return;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
    setState(() => _weeklyCompareDate = picked);
  }

  /// Weeks-only compare popup, mirroring the monthly card's popup
  /// pattern. Delegates to the shared week-picker dialog (same month
  /// stepper, week rows, totals, and future-lock behavior).
  Future<DateTime?> _showWeekCompareDialog() {
    final progress = ref.read(studyProgressProvider);
    final now = DateTime.now();
    return showWeekPickerDialog(
      context: context,
      title: 'Compare with week',
      initialMonday: _monday(_weeklyChartDate),
      initialMonth: DateTime(_viewYear, _viewMonth, 1),
      minutesFor: (monday) =>
          progress.minutesByWeekday(monday, now: now).fold(0, (a, b) => a + b),
    );
  }

  Future<void> _pickComparisonDate({
    required DateTime initialDate,
    required String helpText,
    required ValueChanged<DateTime> onSelected,
  }) async {
    final picked = await _showCompareDatePicker(
      initialDate: initialDate,
      helpText: helpText,
    );
    // Cancel preserves the previously committed comparison date.
    if (picked == null || !mounted) return;
    // Enforce the no-future rule in state logic too, not just visually:
    // normalize to a local calendar date and drop future picks.
    final day = normalizeCompareDay(picked, DateTime.now());
    if (day == null) return;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
    setState(() => onSelected(day));
  }

  /// Pie Compare toggle: the single entry point for the date selector.
  /// No selection -> open the real date picker; selection active ->
  /// clear it again. No always-visible calendar button on the card.
  Future<void> _togglePieCompare() async {
    if (_pieCompareDate != null) {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.selectionClick();
      setState(() => _pieCompareDate = null);
      return;
    }
    await _pickComparisonDate(
      initialDate: _today.subtract(const Duration(days: 1)),
      helpText: 'Choose a day to compare',
      onSelected: (date) => _pieCompareDate = date,
    );
  }

  /// Monthly Compare toggle: the single entry point for month
  /// selection. No compare -> open the shared month-picker sheet (past
  /// months up to and including the current one; future months have no
  /// dates on or before today and are disabled); compare set -> clear it
  /// again.
  Future<void> _toggleMonthlyCompare() async {
    if (_monthlyCompareDate != null) {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.selectionClick();
      setState(() => _monthlyCompareDate = null);
      return;
    }
    final picked = await showMonthPickerSheet(
      context,
      initialMonth:
          _monthlyCompareDate ?? DateTime(_today.year, _today.month - 1, 1),
      firstMonth: DateTime(2000),
      lastMonth: DateTime(_today.year, _today.month, 1),
      title: 'Compare with month',
    );
    if (picked != null && mounted) {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.selectionClick();
      setState(
        () => _monthlyCompareDate = DateTime(picked.year, picked.month, 1),
      );
    }
  }

  /// Reusable Compare/Reset toggle used by every comparison card.
  /// Normal state shows the compare icon; while comparison mode is
  /// active the SAME button becomes a reset icon that stays visible
  /// until tapped, which clears the comparison and restores Compare.
  Widget _compareAction(
    VoidCallback onPressed, {
    String label = 'Compare',
    bool active = false,
  }) {
    final String semanticsLabel = active ? 'Reset comparison' : label;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: active ? AppColors.cta : AppColors.surface2,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Tooltip(
            message: semanticsLabel,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: active
                  ? const Icon(
                      Icons.refresh_rounded,
                      size: 19,
                      color: AppColors.onCta,
                    )
                  : SvgPicture.asset(
                      'assets/icons/compare.svg',
                      width: 19,
                      height: 19,
                      colorFilter: ColorFilter.mode(
                        AppColors.textSecondary,
                        BlendMode.srcIn,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _weeklyStudyTimeCard() {
    final rows = monthWeekRows(_viewYear, _viewMonth);
    final monday = _effectiveWeekMonday(rows);
    final goal = ref.watch(studyProgressProvider).dailyStudyGoalMinutes;
    final weekMinutes = ref
        .read(studyProgressProvider)
        .minutesByWeekday(monday);
    final compareMinutes = _weeklyCompareDate == null
        ? null
        : _minutesForWeek(_weeklyCompareDate!);

    return WeeklyStudyTimeCard(
      monday: monday,
      weekMinutes: weekMinutes,
      dailyGoalMinutes: goal,
      subtitle: '${_monthName(_viewMonth)} $_viewYear',
      compareMinutes: compareMinutes,
      compareRangeLabel: _weeklyCompareDate != null
          ? '${_weekRangeLabel(monday)} vs ${_weekRangeLabel(_weeklyCompareDate!)}'
          : null,
      onCompareTap: _toggleWeeklyCompare,
      compareActive: _weeklyCompareDate != null,
    );
  }

  Widget _monthlyStudyTimeCard() {
    const yTicks = [0, 25, 50, 75, 100];
    final progress = ref.read(studyProgressProvider);
    final weekMinutes = _minutesForMonthWeeks(_monthlyChartDate);
    final compareWeekMinutes = _monthlyCompareDate == null
        ? null
        : _minutesForMonthWeeks(_monthlyCompareDate!);
    final totalMinutes = weekMinutes.fold(0, (sum, minutes) => sum + minutes);
    final compareTotal = compareWeekMinutes?.fold(
      0,
      (sum, minutes) => sum + minutes,
    );
    // Weekly average: mean of the capped daily visual percentages over
    // each Mon–Sun week ((Mon + … + Sun) / 7) — exactly what the weekly
    // chart displays. Spots clamp visually to the 0-100 axis; the stored
    // minutes underneath stay exact.
    final weekPercentages = progress.monthWeekAveragePercentages(
      _monthlyChartDate,
    );
    final compareWeekPercentages = _monthlyCompareDate == null
        ? null
        : progress.monthWeekAveragePercentages(_monthlyCompareDate!);
    final monthTitle = _monthName(_monthlyChartDate.month);
    final pointCount = compareWeekPercentages == null
        ? weekPercentages.length
        : (weekPercentages.length > compareWeekPercentages.length
              ? weekPercentages.length
              : compareWeekPercentages.length);

    return Container(
      key: _monthlyChartCardKey,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('MONTHLY STUDY TIME', style: AppTextStyles.label11),
              ),
              Text(
                '$monthTitle ${_monthlyChartDate.year}',
                style: AppTextStyles.caption12Bold.copyWith(fontSize: 12),
              ),
              const SizedBox(width: 6),
              _compareAction(
                _toggleMonthlyCompare,
                label: 'Compare month',
                active: _monthlyCompareDate != null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_fmtDur(totalMinutes), style: AppTextStyles.display40),
              if (compareTotal != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'vs ${_fmtDur(compareTotal)}',
                    style: AppTextStyles.caption12.copyWith(
                      color: AppColors.blue,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          if (compareWeekMinutes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_monthName(_monthlyChartDate.month)} ${_monthlyChartDate.year} vs ${_monthName(_monthlyCompareDate!.month)} ${_monthlyCompareDate!.year}',
                style: AppTextStyles.label10.copyWith(
                  fontSize: 9,
                  color: AppColors.blue,
                ),
              ),
            ),
          Text(
            'Monthly total · weekly average % of daily goal',
            style: AppTextStyles.label10.copyWith(
              fontSize: 9,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: _monthlyChartVisible
                ? _ChartEntrance(
                    animationKey: '$weekPercentages$compareWeekPercentages',
                    builder: (progress, isEntering, reduceMotion) => LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: (pointCount - 1).toDouble(),
                        minY: 0,
                        maxY: 100,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 25,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: AppColors.track.withValues(alpha: 0.7),
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 25,
                              reservedSize: 30,
                              getTitlesWidget: (value, meta) {
                                if (!yTicks.contains(value.toInt())) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  '${value.toInt()}',
                                  style: AppTextStyles.label10.copyWith(
                                    fontSize: 9,
                                    color: AppColors.textSecondary,
                                  ),
                                );
                              },
                            ),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              interval: 1,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= pointCount) {
                                  return const SizedBox.shrink();
                                }
                                return SideTitleWidget(
                                  axisSide: meta.axisSide,
                                  space: 5,
                                  child: Text(
                                    'W${index + 1}',
                                    style: AppTextStyles.label10.copyWith(
                                      fontSize: 10,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (
                                var index = 0;
                                index < weekPercentages.length;
                                index++
                              )
                                FlSpot(
                                  index.toDouble(),
                                  weekPercentages[index].clamp(0.0, 100.0) *
                                      progress,
                                ),
                            ],
                            isCurved: false,
                            color: AppColors.cta,
                            barWidth: 3,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) =>
                                  FlDotCirclePainter(
                                    radius: 3,
                                    color: AppColors.cta,
                                    strokeWidth: 1.5,
                                    strokeColor: AppColors.surface,
                                  ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.cta.withValues(alpha: 0.12),
                            ),
                          ),
                          if (compareWeekPercentages != null)
                            LineChartBarData(
                              spots: [
                                for (
                                  var index = 0;
                                  index < compareWeekPercentages.length;
                                  index++
                                )
                                  FlSpot(
                                    index.toDouble(),
                                    compareWeekPercentages[index].clamp(
                                          0.0,
                                          100.0,
                                        ) *
                                        progress,
                                  ),
                              ],
                              isCurved: false,
                              color: AppColors.blue,
                              barWidth: 3,
                              dotData: FlDotData(
                                show: true,
                                getDotPainter:
                                    (spot, percent, barData, index) =>
                                        FlDotCirclePainter(
                                          radius: 3,
                                          color: AppColors.blue,
                                          strokeWidth: 1.5,
                                          strokeColor: AppColors.surface,
                                        ),
                              ),
                            ),
                        ],
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (spots) => [
                              for (final spot in spots)
                                if (spot.x.toInt() <
                                    (spot.barIndex == 0
                                        ? weekPercentages.length
                                        : compareWeekPercentages?.length ?? 0))
                                  LineTooltipItem(
                                    'Week ${spot.x.toInt() + 1}: '
                                    '${formatMonthlyPercentage(spot.barIndex == 0 ? weekPercentages[spot.x.toInt()] : compareWeekPercentages![spot.x.toInt()])}',
                                    AppTextStyles.caption12Bold.copyWith(
                                      color: spot.bar.color ?? AppColors.cta,
                                    ),
                                  )
                                else
                                  null,
                            ],
                          ),
                        ),
                      ),
                      duration: isEntering || reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                    ),
                  )
                : const SizedBox.expand(),
          ),
          if (compareWeekPercentages != null) ...[
            const SizedBox(height: 4),
            const _CompareLegend(
              firstLabel: 'Selected month',
              secondLabel: 'Compare month',
            ),
          ],
        ],
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  String _formatShortDate(DateTime date) => '${date.month}/${date.day}';

  String _weekRangeLabel(DateTime date) {
    final start = _monday(date);
    final end = start.add(const Duration(days: 6));
    return '${_formatShortDate(start)}–${_formatShortDate(end)}';
  }

  /// Attendance month grid on the real table_calendar package (Monday
  /// start, swipeable months). Day dots: green = studied that date,
  /// red = ended date with nothing, strikethrough = before first launch.
  Widget _monthGrid() {
    Widget dayNumber(DateTime day, {required bool muted}) {
      return Text(
        '${day.day}',
        style: AppTextStyles.caption12Bold.copyWith(
          fontSize: 12,
          decoration: _disabled(day) ? TextDecoration.lineThrough : null,
          color: muted ? AppColors.textMuted : AppColors.textPrimary,
        ),
      );
    }

    Widget dot(Color color) {
      return Container(
        width: 4,
        height: 4,
        margin: const EdgeInsets.only(top: 1),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }

    Widget statusDot(DateTime day) {
      if (_disabled(day)) return const SizedBox(width: 4, height: 5);
      if (_present(day)) return dot(AppColors.green);
      if (_absent(day)) return dot(Colors.redAccent);
      return const SizedBox(width: 4, height: 5);
    }

    return TableCalendar(
      firstDay: DateTime(2000),
      lastDay: DateTime(2100),
      focusedDay: DateTime(_viewYear, _viewMonth, 1),
      calendarFormat: CalendarFormat.month,
      availableCalendarFormats: const {CalendarFormat.month: 'Month'},
      startingDayOfWeek: StartingDayOfWeek.monday,
      headerVisible: false,
      // The card keeps its own M–S weekday row above the grid.
      daysOfWeekVisible: false,
      rowHeight: 38,
      calendarStyle: const CalendarStyle(
        outsideDaysVisible: true,
        markersMaxCount: 1,
        markerSize: 4,
      ),
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, _) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [dayNumber(day, muted: false), statusDot(day)],
        ),
        todayBuilder: (context, day, _) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.cta,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                style: AppTextStyles.caption12Bold.copyWith(
                  fontSize: 12,
                  color: AppColors.onCta,
                ),
              ),
            ),
            statusDot(day),
          ],
        ),
        outsideBuilder: (context, day, _) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            dayNumber(day, muted: true),
            const SizedBox(width: 4, height: 5),
          ],
        ),
        disabledBuilder: (context, day, _) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            dayNumber(day, muted: true),
            const SizedBox(width: 4, height: 5),
          ],
        ),
      ),
      enabledDayPredicate: (day) => !_disabled(day),
      onPageChanged: (page) {
        if (!mounted) return;
        setState(() {
          _viewYear = page.year;
          _viewMonth = page.month;
          _snapWeeklySelection();
        });
      },
    );
  }
}

class _Dow extends StatelessWidget {
  final String d;
  const _Dow(this.d);
  @override
  Widget build(BuildContext context) {
    return Text(d, style: AppTextStyles.label10);
  }
}

/// Today pie card: goal-relative slices (fixes 100%-on-start bug).
/// Buckets: Night [00:00, 06:00), Morning [06:00, 12:00),
/// Afternoon [12:00, 18:00), Evening [18:00, 24:00).
/// Slice % = periodMinutes / dailyGoal * 100, remainder = track.
/// Period labels below must stay in sync with
/// [timePeriodIndexForHour] in analytics_models.dart.
class _DaypartPieCard extends StatelessWidget {
  final List<int> minutesByPart;
  final List<int>? comparisonMinutesByPart;
  final DateTime? comparisonDate;
  final VoidCallback onCompare;
  final int goalMinutes;

  const _DaypartPieCard({
    required this.minutesByPart,
    required this.comparisonMinutesByPart,
    required this.comparisonDate,
    required this.onCompare,
    this.goalMinutes = 480,
  });

  static const _parts = [
    ('Morning', '6:00 AM – 11:59 AM', AppColors.cta),
    ('Afternoon', '12:00 PM – 5:59 PM', AppColors.primary),
    ('Evening', '6:00 PM – 11:59 PM', AppColors.green),
    ('Night', '12:00 AM – 5:59 AM', AppColors.blue),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Today',
                  textAlign: TextAlign.left,
                  style: AppTextStyles.section18,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: comparisonDate != null
                    ? 'Reset comparison'
                    : 'Compare day',
                child: Material(
                  color: comparisonDate != null
                      ? AppColors.cta
                      : AppColors.surface2,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onCompare,
                    child: Tooltip(
                      message: comparisonDate != null
                          ? 'Reset comparison'
                          : 'Compare another day',
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: comparisonDate != null
                            ? const Icon(
                                Icons.refresh_rounded,
                                size: 19,
                                color: AppColors.onCta,
                              )
                            : SvgPicture.asset(
                                'assets/icons/compare.svg',
                                width: 19,
                                height: 19,
                                colorFilter: const ColorFilter.mode(
                                  AppColors.textSecondary,
                                  BlendMode.srcIn,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              if (comparisonDate != null) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    '${comparisonDate!.month}/${comparisonDate!.day}',
                    style: AppTextStyles.caption12Bold.copyWith(
                      color: AppColors.blue,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Material(
                color: AppColors.surface2,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  splashColor: AppColors.primary.withValues(alpha: 0.3),
                  onTap: () {
                    SystemSound.play(SystemSoundType.click);
                    HapticFeedback.selectionClick();
                    showDialog(
                      context: context,
                      builder: (ctx) =>
                          _DaypartHelpDialog(goalLabel: _fmtDur(goalMinutes)),
                    );
                  },
                  child: Tooltip(
                    message: 'About day parts',
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: SvgPicture.asset(
                        'assets/icons/note.svg',
                        width: 19,
                        height: 19,
                        colorFilter: const ColorFilter.mode(
                          AppColors.textSecondary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            formatTotalStudied(
              minutesByPart.fold(0, (a, b) => a + b),
              goalMinutes,
            ),
            textAlign: TextAlign.center,
            style: AppTextStyles.caption12Bold,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GoalPieView(
                mins: minutesByPart,
                label: 'Today',
                animationKey:
                    'today-${comparisonDate == null ? 'none' : _dkey(comparisonDate!)}-${minutesByPart.join(',')}-$goalMinutes',
                goal: goalMinutes,
              ),
              if (comparisonMinutesByPart != null) ...[
                const SizedBox(width: 8),
                _GoalPieView(
                  mins: comparisonMinutesByPart!,
                  label: '${comparisonDate!.month}/${comparisonDate!.day}',
                  animationKey:
                      'compare-${_dkey(comparisonDate!)}-${comparisonMinutesByPart!.join(',')}-$goalMinutes',
                  goal: goalMinutes,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              for (int i = 0; i < _parts.length; i++)
                Text(
                  '• ${_parts[i].$1}',
                  style: AppTextStyles.caption12Bold.copyWith(
                    color: _parts[i].$3,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Polished "How it works" dialog: distinct heading, aligned
/// dot + period rows in chart colors, and a readable goal paragraph.
/// Scrolls internally so it stays usable on small screens and large
/// text scales; standard modal barrier dimming is preserved.
class _DaypartHelpDialog extends StatelessWidget {
  final String goalLabel;
  const _DaypartHelpDialog({required this.goalLabel});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Text('How it works', style: AppTextStyles.section18),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.55,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              for (int i = 0; i < _DaypartPieCard._parts.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _DaypartPieCard._parts[i].$3,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _DaypartPieCard._parts[i].$1,
                              style: AppTextStyles.body14Bold,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _DaypartPieCard._parts[i].$2,
                              style: AppTextStyles.secondary14,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Sessions are bucketed by local time. Slices show % of '
                'the shared daily goal ($goalLabel), not % of today.',
                style: AppTextStyles.body14.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.cta,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Text('Got it', style: AppTextStyles.body14Bold),
        ),
      ],
    );
  }
}

class _ChartEntrance extends StatefulWidget {
  final Object animationKey;
  final Widget Function(double progress, bool isEntering, bool reduceMotion)
  builder;

  const _ChartEntrance({required this.animationKey, required this.builder});

  @override
  State<_ChartEntrance> createState() => _ChartEntranceState();
}

class _ChartEntranceState extends State<_ChartEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion && _started) return;
    _reduceMotion = reduceMotion;
    if (_reduceMotion) {
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _ChartEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationKey == widget.animationKey) return;
    if (_reduceMotion) {
      _controller.value = 1;
    } else {
      _started = true;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = Curves.easeOutCubic.transform(_controller.value);
        return Opacity(
          opacity: progress,
          child: widget.builder(
            progress,
            !_reduceMotion && _controller.isAnimating,
            _reduceMotion,
          ),
        );
      },
    );
  }
}

/// Goal-relative donut with tap-to-inspect slices (native equivalent of a
/// chart tooltip: tapping a slice enlarges it and names it below the pie).
class _GoalPieView extends StatefulWidget {
  final List<int> mins;
  final String label;
  final String animationKey;
  final int goal;

  const _GoalPieView({
    required this.mins,
    required this.label,
    required this.animationKey,
    required this.goal,
  });

  @override
  State<_GoalPieView> createState() => _GoalPieViewState();
}

class _GoalPieViewState extends State<_GoalPieView> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal <= 0 ? 480 : widget.goal;
    final values = [for (final m in widget.mins) m / goal * 100];
    final done = values.fold(0.0, (a, b) => a + b).clamp(0.0, 100.0);
    final remaining = (100 - done).clamp(0.0, 100.0);
    final total = widget.mins.fold(0, (a, b) => a + b);

    final sections = <PieChartSectionData>[];
    final sliceTips = <String>[];
    if (total == 0) {
      sections.add(
        PieChartSectionData(
          value: 100,
          color: AppColors.track,
          radius: 76,
          showTitle: false,
        ),
      );
      sliceTips.add('No sessions yet');
    } else {
      for (var i = 0; i < values.length; i++) {
        if (widget.mins[i] <= 0) continue;
        final touched = _touched == sections.length;
        sections.add(
          PieChartSectionData(
            value: values[i],
            color: _DaypartPieCard._parts[i].$3,
            radius: touched ? 84 : 76,
            showTitle: false,
          ),
        );
        sliceTips.add(
          '${_DaypartPieCard._parts[i].$1}: ${_fmtDur(widget.mins[i])} · ${formatMonthlyPercentage(values[i])} of goal',
        );
      }
      final touched = _touched == sections.length;
      sections.add(
        PieChartSectionData(
          value: remaining,
          color: AppColors.track,
          radius: touched ? 84 : 76,
          showTitle: false,
        ),
      );
      sliceTips.add('Remaining of goal');
    }
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 170,
            child: _ChartEntrance(
              animationKey: widget.animationKey,
              builder: (progress, isEntering, reduceMotion) {
                final animatedSections = [
                  for (final section in sections)
                    PieChartSectionData(
                      value: section.value == 100 && total == 0
                          ? 100
                          : section.color == AppColors.track
                          ? 100 - done * progress
                          : section.value * progress,
                      color: section.color,
                      radius: section.radius,
                      showTitle: section.showTitle,
                    ),
                ];
                return PieChart(
                  PieChartData(
                    // Closed pie (no hole) with no gaps between periods.
                    centerSpaceRadius: 0,
                    sectionsSpace: 0,
                    startDegreeOffset: -90,
                    sections: animatedSections,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        final i =
                            response?.touchedSection?.touchedSectionIndex ?? -1;
                        if (i != _touched) setState(() => _touched = i);
                      },
                    ),
                  ),
                  duration: isEntering || reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 650),
                  curve: Curves.easeInOutCubic,
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (total == 0)
            Text(
              'No sessions yet · 0.00% of goal',
              textAlign: TextAlign.center,
              style: AppTextStyles.label10.copyWith(
                color: AppColors.textMuted,
                fontSize: 9,
              ),
            )
          else if (_touched >= 0 && _touched < sliceTips.length)
            Text(
              sliceTips[_touched],
              textAlign: TextAlign.center,
              style: AppTextStyles.caption12Bold.copyWith(fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          else
            Text(
              '${formatDayStudied(widget.label, total)} · ${formatMonthlyPercentage(total / goal * 100)} of goal',
              textAlign: TextAlign.center,
              style: AppTextStyles.label10.copyWith(
                color: AppColors.textSecondary,
                fontSize: 9,
              ),
            ),
        ],
      ),
    );
  }
}

class _CompareLegend extends StatelessWidget {
  final String firstLabel;
  final String secondLabel;

  const _CompareLegend({required this.firstLabel, required this.secondLabel});

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTextStyles.label10.copyWith(
            fontSize: 9,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        item(AppColors.cta, firstLabel),
        const SizedBox(width: 18),
        item(AppColors.blue, secondLabel),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.label10),
      ],
    );
  }
}

/// The two-button session control: CHECK IN starts or resumes, CHECK OUT
/// pauses. Exactly two buttons; each disables itself when its action would
/// be a no-op (check-in while running, check-out while paused/absent).
class _CheckInOutButtons extends StatelessWidget {
  final bool checkInEnabled;
  final bool checkOutEnabled;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  const _CheckInOutButtons({
    required this.checkInEnabled,
    required this.checkOutEnabled,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  Widget _button({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: enabled ? AppColors.cta : AppColors.track,
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          borderRadius: BorderRadius.circular(100),
          splashColor: Colors.black26,
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                label,
                style: AppTextStyles.body14Bold.copyWith(
                  color: enabled ? AppColors.onCta : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _button(label: 'Check In', enabled: checkInEnabled, onTap: onCheckIn),
        const SizedBox(width: 12),
        _button(
          label: 'Check Out',
          enabled: checkOutEnabled,
          onTap: onCheckOut,
        ),
      ],
    );
  }
}
