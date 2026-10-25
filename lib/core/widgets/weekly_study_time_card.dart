import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fl_chart/fl_chart.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Formats minutes into human-readable duration ('45m', '2h', '2h 15m').
String formatWeeklyDuration(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final r = minutes % 60;
  return r == 0 ? '${h}h' : '${h}h ${r}m';
}

/// Computes goal percentage clamped to 0..100.
double computeGoalPercent(int minutes, int goalMinutes) {
  final target = goalMinutes <= 0 ? 480 : goalMinutes;
  return (minutes / target * 100).clamp(0.0, 100.0);
}

/// Entrance animation controller for smooth chart bar growth.
class _WeeklyChartEntrance extends StatefulWidget {
  final Object animationKey;
  final Widget Function(double progress, bool isEntering, bool reduceMotion) builder;

  const _WeeklyChartEntrance({
    required this.animationKey,
    required this.builder,
  });

  @override
  State<_WeeklyChartEntrance> createState() => _WeeklyChartEntranceState();
}

class _WeeklyChartEntranceState extends State<_WeeklyChartEntrance>
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
  void didUpdateWidget(covariant _WeeklyChartEntrance oldWidget) {
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
      builder: (context, _) => widget.builder(
        _controller.value,
        !_started,
        _reduceMotion,
      ),
    );
  }
}

/// The official StudyUP Weekly Progress Card component.
/// Used identically across Insights and Community screens to ensure consistent
/// layout, styling, typography, colors, bars, labels, and calculations.
class WeeklyStudyTimeCard extends StatelessWidget {
  /// Monday date of the week being displayed.
  final DateTime monday;

  /// 7-day study minutes list [Mon, Tue, Wed, Thu, Fri, Sat, Sun].
  final List<int> weekMinutes;

  /// Daily study goal in minutes (default 480 if not set).
  final int dailyGoalMinutes;

  /// Card title header (defaults to 'WEEKLY STUDY TIME').
  final String title;

  /// Optional subtitle e.g. month name or person's context.
  final String? subtitle;

  /// Optional comparison 7-day minutes list (e.g. compare week or friend).
  final List<int>? compareMinutes;

  /// Label shown beside total duration when comparing (e.g. 'vs 1h 30m').
  final String? compareLabel;

  /// Subtitle shown under duration when comparing (e.g. 'Oct 12-18 vs Oct 5-11').
  final String? compareRangeLabel;

  /// Primary bar color (defaults to brand CTA gold #FDD679).
  final Color primaryBarColor;

  /// Comparison bar color (defaults to blue #7DD3E8).
  final Color compareBarColor;

  /// Name of primary series in touch tooltip (defaults to 'Selected').
  final String primaryLabel;

  /// Name of compare series in touch tooltip (defaults to 'Compare').
  final String compareName;

  /// Callback when compare button is tapped.
  final VoidCallback? onCompareTap;

  /// Whether compare mode is active.
  final bool compareActive;

  /// Tooltip message for compare button.
  final String compareButtonLabel;

  /// Optional leading icon displayed before title.
  final Widget? leadingIcon;

  /// Optional widget displayed on top right next to date.
  final Widget? headerAction;

  /// Optional footer widget displayed below chart and legend.
  final Widget? footer;

  /// Empty notice text (defaults to 'No study time this week yet.').
  final String? emptyNotice;

  /// Legend label for first series (defaults to 'Selected week').
  final String firstLegendLabel;

  /// Legend label for second series (defaults to 'Compare week').
  final String secondLegendLabel;

  const WeeklyStudyTimeCard({
    super.key,
    required this.monday,
    required this.weekMinutes,
    this.dailyGoalMinutes = 480,
    this.title = 'WEEKLY STUDY TIME',
    this.subtitle,
    this.compareMinutes,
    this.compareLabel,
    this.compareRangeLabel,
    this.primaryBarColor = AppColors.cta,
    this.compareBarColor = AppColors.blue,
    this.primaryLabel = 'Selected',
    this.compareName = 'Compare',
    this.onCompareTap,
    this.compareActive = false,
    this.compareButtonLabel = 'Compare week',
    this.leadingIcon,
    this.headerAction,
    this.footer,
    this.emptyNotice,
    this.firstLegendLabel = 'Selected week',
    this.secondLegendLabel = 'Compare week',
  });

  @override
  Widget build(BuildContext context) {
    final sunday = monday.add(const Duration(days: 6));
    final dateLabel = '${monday.month}/${monday.day} – ${sunday.month}/${sunday.day}';
    final totalMinutes = weekMinutes.fold(0, (sum, minutes) => sum + minutes);
    final compareTotal = compareMinutes?.fold(0, (sum, minutes) => sum + minutes);

    double pct(int m) => computeGoalPercent(m, dailyGoalMinutes);
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const yTicks = [0, 25, 50, 75, 100];

    return Container(
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
              if (leadingIcon != null) ...[
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: leadingIcon!,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.label11,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                dateLabel,
                style: AppTextStyles.caption12Bold.copyWith(fontSize: 12),
              ),
              if (onCompareTap != null) ...[
                const SizedBox(width: 6),
                _buildCompareButton(),
              ] else if (headerAction != null) ...[
                const SizedBox(width: 6),
                headerAction!,
              ],
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            Text(
              subtitle!,
              style: AppTextStyles.label10.copyWith(
                fontSize: 9,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 6),
          ] else ...[
            const SizedBox(height: 6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatWeeklyDuration(totalMinutes), style: AppTextStyles.display40),
              if (compareTotal != null || compareLabel != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    compareLabel ?? 'vs ${formatWeeklyDuration(compareTotal ?? 0)}',
                    style: AppTextStyles.caption12.copyWith(
                      color: compareBarColor,
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
          if (compareRangeLabel != null && compareRangeLabel!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                compareRangeLabel!,
                style: AppTextStyles.label10.copyWith(
                  fontSize: 9,
                  color: compareBarColor,
                ),
              ),
            ),
          Text(
            'Daily % of goal · 100 = full daily goal',
            style: AppTextStyles.label10.copyWith(
              fontSize: 9,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          if (totalMinutes == 0) ...[
            const SizedBox(height: 8),
            Text(
              emptyNotice ?? 'No study time this week yet.',
              style: AppTextStyles.label10.copyWith(
                fontSize: 9,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: _WeeklyChartEntrance(
              animationKey: '$weekMinutes$compareMinutes',
              builder: (progress, isEntering, reduceMotion) => BarChart(
                BarChartData(
                  minY: 0,
                  maxY: 100,
                  alignment: BarChartAlignment.spaceAround,
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
                    rightTitles: const AxisTitles(
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
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= weekMinutes.length) {
                            return const SizedBox.shrink();
                          }
                          final day = monday.add(Duration(days: index));
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            space: 5,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  weekdays[index],
                                  style: AppTextStyles.label10.copyWith(
                                    fontSize: 9,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                Text(
                                  '${day.day}',
                                  style: AppTextStyles.label10.copyWith(
                                    fontSize: 8,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(7, (index) {
                    final minutes = index < weekMinutes.length ? weekMinutes[index] : 0;
                    final percent = pct(minutes);
                    final hasCompare = compareMinutes != null && index < compareMinutes!.length;
                    return BarChartGroupData(
                      x: index,
                      barsSpace: hasCompare ? 3 : 0,
                      barRods: [
                        BarChartRodData(
                          toY: percent * progress,
                          width: hasCompare ? 14 : 32,
                          color: minutes > 0 ? primaryBarColor : AppColors.track,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5),
                          ),
                        ),
                        if (hasCompare)
                          BarChartRodData(
                            toY: pct(compareMinutes![index]) * progress,
                            width: 14,
                            color: compareMinutes![index] > 0
                                ? compareBarColor
                                : AppColors.track,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                      ],
                    );
                  }),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final isPrimary = rodIndex == 0;
                        final duration = isPrimary
                            ? (group.x < weekMinutes.length ? weekMinutes[group.x] : 0)
                            : (compareMinutes != null && group.x < compareMinutes!.length
                                ? compareMinutes![group.x]
                                : 0);
                        final labelName = isPrimary ? primaryLabel : compareName;
                        return BarTooltipItem(
                          '$labelName: ${formatWeeklyDuration(duration)} · ${rod.toY.toStringAsFixed(2)}% of goal',
                          AppTextStyles.caption12Bold.copyWith(
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                duration: isEntering || reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
              ),
            ),
          ),
          if (compareMinutes != null || compareLabel != null || compareRangeLabel != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(primaryBarColor, firstLegendLabel),
                const SizedBox(width: 18),
                _buildLegendItem(compareBarColor, secondLegendLabel),
              ],
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 12),
            footer!,
          ],
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) => Row(
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

  Widget _buildCompareButton() {
    final semanticsLabel = compareActive ? 'Reset comparison' : compareButtonLabel;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: compareActive ? AppColors.cta : AppColors.surface2,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onCompareTap,
          child: Tooltip(
            message: semanticsLabel,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: compareActive
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
    );
  }
}
