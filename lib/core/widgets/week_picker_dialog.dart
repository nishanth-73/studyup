import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../../features/progress/data/study_gamification.dart';
import 'date_picker_sheet.dart';
import 'ui_kit.dart';

/// Shared week-picker bottom sheet: the exact interaction and visual
/// language of the shared calendar picker.
///
/// A month stepper walks back through past months up to the present
/// month — never into the future. Each week row (W1..Wn, Monday-start,
/// same rows the monthly chart uses) shows its real date range and a
/// recorded total supplied by [minutesFor]; rows starting after today
/// are shown locked. Tapping a row returns its Monday; Cancel or a
/// barrier dismiss returns null.
///
/// Used by Progress for week comparison so the app has one week-picker
/// implementation.
Future<DateTime?> showWeekPickerDialog({
  required BuildContext context,
  required String title,
  required DateTime initialMonday,
  required int Function(DateTime monday) minutesFor,
  DateTime? initialMonth,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thisMonth = DateTime(now.year, now.month, 1);
  var month =
      initialMonth ?? DateTime(initialMonday.year, initialMonday.month, 1);
  if (month.isAfter(thisMonth)) month = thisMonth;
  final selected = DateTime(
    initialMonday.year,
    initialMonday.month,
    initialMonday.day,
  );

  String fmtDur(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final r = minutes % 60;
    return r == 0 ? '${h}h' : '${h}h ${r}m';
  }

  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final rows = monthWeekRows(month.year, month.month);
        final canBack = month.isAfter(DateTime(2000));
        final canForward = month.isBefore(thisMonth);
        return PickerSheetFrame(
          title: title,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  PickerCircleButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Previous month',
                    onTap: canBack
                        ? () => setSheet(() {
                            month = DateTime(month.year, month.month - 1, 1);
                          })
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      '${_monthName(month.month)} ${month.year}',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body16Bold,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (canForward)
                    PickerCircleButton(
                      icon: Icons.chevron_right_rounded,
                      tooltip: 'Next month',
                      onTap: () => setSheet(() {
                        month = DateTime(month.year, month.month + 1, 1);
                      }),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Pill(
                        'This month',
                        background: AppColors.track,
                        foreground: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (final row in rows)
                Builder(
                  builder: (context) {
                    final enabled = !row.monday.isAfter(today);
                    final isCurrent = row.contains(today);
                    final isSelected = row.monday.isAtSameMomentAs(selected);
                    final total = minutesFor(row.monday);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Material(
                        color: enabled
                            ? isSelected
                                  ? AppColors.cta.withValues(alpha: 0.14)
                                  : AppColors.surface2
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: enabled
                              ? () => Navigator.pop(ctx, row.monday)
                              : null,
                          child: Container(
                            decoration: isSelected
                                ? BoxDecoration(
                                    border: Border.all(
                                      color: AppColors.cta.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  )
                                : null,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${row.label} · ${row.rangeLabel()}'
                                        '${isCurrent ? ' · This week' : ''}',
                                        style: AppTextStyles.body14Bold
                                            .copyWith(
                                              color: enabled
                                                  ? AppColors.textPrimary
                                                  : AppColors.textMuted,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        total == 0
                                            ? 'No study time yet'
                                            : '${fmtDur(total)} studied',
                                        style: AppTextStyles.caption12.copyWith(
                                          color: enabled
                                              ? AppColors.textSecondary
                                              : AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!enabled)
                                  const Icon(
                                    Icons.lock_outline,
                                    size: 16,
                                    color: AppColors.textMuted,
                                  )
                                else if (isSelected)
                                  const Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: AppColors.cta,
                                  )
                                else
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: AppColors.textSecondary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
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
