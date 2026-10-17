import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'ui_kit.dart';

const _monthNames = [
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

const _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

/// Shared bottom-sheet day picker: rounded top corners, centered
/// month/year heading with circular previous/next controls, a Monday-first
/// seven-column calendar, a filled highlight for the selected day, an
/// outlined "TODAY" marker, and a full-width Done button.
///
/// Days outside [firstDate]..[lastDate] are disabled and non-selectable
/// (taps ignored, excluded from accessibility actions); month navigation
/// stops at the boundary months. Returns the picked date (day precision)
/// or null when dismissed without confirming.
Future<DateTime?> showCalendarPickerSheet(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'Select date',
}) {
  final first = _atMidnight(firstDate);
  final last = _atMidnight(lastDate);
  var initial = _atMidnight(initialDate);
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => _CalendarPickerSheet(
      title: title,
      first: first,
      last: last,
      initial: initial,
    ),
  );
}

/// Shared bottom-sheet month picker (same visual language as the calendar):
/// centered year heading with circular controls and a 3x4 grid of month
/// chips. Months outside [firstMonth]..[lastMonth] are disabled. Returns
/// the first day of the picked month, or null when dismissed.
Future<DateTime?> showMonthPickerSheet(
  BuildContext context, {
  required DateTime initialMonth,
  required DateTime firstMonth,
  required DateTime lastMonth,
  String title = 'Select month',
}) {
  final first = DateTime(firstMonth.year, firstMonth.month, 1);
  final last = DateTime(lastMonth.year, lastMonth.month, 1);
  var initial = DateTime(initialMonth.year, initialMonth.month, 1);
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => _MonthPickerSheet(
      title: title,
      first: first,
      last: last,
      initial: initial,
    ),
  );
}

/// Shared sheet chrome: surface background, large rounded top corners, a
/// grabber, a title with an explicit Cancel action, and a scroll-safe
/// body that respects system insets and small screens.
class PickerSheetFrame extends StatelessWidget {
  final String title;
  final Widget child;
  const PickerSheetFrame({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.track,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 10, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title, style: AppTextStyles.section18),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.cta,
                      ),
                      child: Text('Cancel', style: AppTextStyles.body14Bold),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    4,
                    20,
                    16 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular previous/next control used by the picker sheets.
class PickerCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const PickerCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap != null ? AppColors.surface2 : Colors.transparent,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        iconSize: 20,
        color: AppColors.textPrimary,
        disabledColor: AppColors.textMuted.withValues(alpha: 0.4),
        icon: Icon(icon),
      ),
    );
  }
}

class _CalendarPickerSheet extends StatefulWidget {
  final String title;
  final DateTime first;
  final DateTime last;
  final DateTime initial;
  const _CalendarPickerSheet({
    required this.title,
    required this.first,
    required this.last,
    required this.initial,
  });

  @override
  State<_CalendarPickerSheet> createState() => _CalendarPickerSheetState();
}

class _CalendarPickerSheetState extends State<_CalendarPickerSheet> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _month = DateTime(_selected.year, _selected.month, 1);
  }

  DateTime get _firstMonth =>
      DateTime(widget.first.year, widget.first.month, 1);
  DateTime get _lastMonth => DateTime(widget.last.year, widget.last.month, 1);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = _atMidnight(now);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = _month.weekday - 1;

    final cells = <Widget>[];
    for (var i = 0; i < 42; i++) {
      final dayNumber = i - leading + 1;
      if (dayNumber < 1 || dayNumber > daysInMonth) {
        cells.add(const SizedBox.shrink());
        continue;
      }
      final day = DateTime(_month.year, _month.month, dayNumber);
      final enabled =
          !day.isBefore(widget.first) && !day.isAfter(widget.last);
      cells.add(
        _DayCell(
          day: day,
          isToday: day == today,
          isSelected: day == _selected,
          isEnabled: enabled,
          onTap: () => setState(() => _selected = day),
        ),
      );
    }

    return PickerSheetFrame(
      title: widget.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              PickerCircleButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous month',
                onTap: _month.isAfter(_firstMonth)
                    ? () => setState(
                        () => _month =
                            DateTime(_month.year, _month.month - 1, 1),
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  '${_monthNames[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body16Bold,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PickerCircleButton(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next month',
                onTap: _month.isBefore(_lastMonth)
                    ? () => setState(
                        () => _month =
                            DateTime(_month.year, _month.month + 1, 1),
                      )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final label in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.label11.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (_, index) => cells[index],
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.pop(context, _selected),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onTap;
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final numberStyle = isSelected
        ? AppTextStyles.body14Bold.copyWith(color: AppColors.onCta)
        : AppTextStyles.body14.copyWith(
            color: isEnabled
                ? AppColors.textPrimary
                : AppColors.textMuted.withValues(alpha: 0.45),
          );
    return Semantics(
      button: true,
      enabled: isEnabled,
      selected: isSelected,
      label: '${_monthNames[day.month - 1]} ${day.day}, ${day.year}',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: isEnabled ? onTap : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.cta : Colors.transparent,
                border: !isSelected && isToday
                    ? Border.all(
                        color: AppColors.cta.withValues(alpha: 0.7),
                        width: 1.4,
                      )
                    : null,
              ),
              child: Text('${day.day}', style: numberStyle),
            ),
            if (isToday && isEnabled)
              Text(
                'TODAY',
                style: AppTextStyles.label10.copyWith(
                  color: isSelected ? AppColors.cta : AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthPickerSheet extends StatefulWidget {
  final String title;
  final DateTime first;
  final DateTime last;
  final DateTime initial;
  const _MonthPickerSheet({
    required this.title,
    required this.first,
    required this.last,
    required this.initial,
  });

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  late int _year;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _year = widget.initial.year;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);

    return PickerSheetFrame(
      title: widget.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              PickerCircleButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous year',
                onTap: _year > widget.first.year
                    ? () => setState(() => _year--)
                    : null,
              ),
              Expanded(
                child: Text(
                  '$_year',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body16Bold,
                ),
              ),
              PickerCircleButton(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next year',
                onTap: _year < widget.last.year
                    ? () => setState(() => _year++)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 12,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2.4,
            ),
            itemBuilder: (_, index) {
              final month = DateTime(_year, index + 1, 1);
              final enabled = !month.isBefore(widget.first) &&
                  !month.isAfter(widget.last);
              final selected = month == _selected;
              final isCurrent = month == currentMonth;
              final textStyle = selected
                  ? AppTextStyles.body14Bold.copyWith(color: AppColors.onCta)
                  : AppTextStyles.body14.copyWith(
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textMuted.withValues(alpha: 0.45),
                    );
              return Padding(
                padding: const EdgeInsets.all(3),
                child: Material(
                  color: selected
                      ? AppColors.cta
                      : enabled
                      ? AppColors.surface2
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: enabled
                        ? () => setState(() => _selected = month)
                        : null,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: !selected && enabled && isCurrent
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.cta.withValues(alpha: 0.7),
                                width: 1.4,
                              ),
                            )
                          : null,
                      child: Text(_monthShort[index], style: textStyle),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.pop(context, _selected),
          ),
        ],
      ),
    );
  }
}
