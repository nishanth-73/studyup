import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../home/presentation/home_controller.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeControllerProvider);
    final controller = ref.read(homeControllerProvider.notifier);
    final tasks = state.selectedTasks;
    final done = tasks.where((task) => task.isDone).length;
    final totalMinutes = tasks.fold(0, (sum, task) => sum + task.minutes);
    final dateLabel =
        '${_weekday(state.selectedDate.weekday)}, ${state.selectedDate.day} ${_month(state.selectedDate.month)}';

    return AppShell(
      currentIndex: 0,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          children: [
            Text('Study Plan', style: AppTextStyles.title30),
            Text(dateLabel, style: AppTextStyles.secondary14),
            const SizedBox(height: 14),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: state.weekDates.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final date = state.weekDates[index];
                  final selected =
                      date.year == state.selectedDate.year &&
                      date.month == state.selectedDate.month &&
                      date.day == state.selectedDate.day;
                  return Material(
                    color: selected ? AppColors.cta : AppColors.surface,
                    borderRadius: BorderRadius.circular(23),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(23),
                      onTap: () {
                        SystemSound.play(SystemSoundType.click);
                        HapticFeedback.selectionClick();
                        controller.selectDate(date);
                      },
                      child: SizedBox(
                        width: 46,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _weekday(date.weekday).substring(0, 1),
                              style: AppTextStyles.label11.copyWith(
                                color: selected
                                    ? AppColors.onCta
                                    : AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              '${date.day}',
                              style: AppTextStyles.body16Bold.copyWith(
                                color: selected
                                    ? AppColors.onCta
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  '$done of ${tasks.length} tasks done',
                  style: AppTextStyles.body14Bold,
                ),
                const Spacer(),
                Text(
                  _formatDuration(totalMinutes),
                  style: AppTextStyles.caption12,
                ),
              ],
            ),
            const SizedBox(height: 6),
            AppProgressBar(value: tasks.isEmpty ? 0 : done / tasks.length),
            const SizedBox(height: 14),
            if (tasks.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      'No tasks planned for this day.',
                      style: AppTextStyles.body15,
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('Add tasks from Home'),
                    ),
                  ],
                ),
              )
            else
              for (final task in tasks)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: task.isDone,
                        onChanged: (_) => controller.toggleTask(task.id),
                        activeColor: AppColors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(task.title, style: AppTextStyles.body16Bold),
                            Text(
                              task.description,
                              style: AppTextStyles.caption12,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${task.startLabel} – ${task.endLabel} · ${task.durationLabel}',
                              style: AppTextStyles.caption12,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            // Scroll clearance above the floating nav (AppShell math).
            SizedBox(height: AppShell.scrollClearance(context)),
          ],
        ),
      ),
    );
  }
}

String _weekday(int day) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][day - 1];

String _month(int month) => const [
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
][month - 1];

String _formatDuration(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return hours == 0 ? '${remainder}m' : '${hours}h ${remainder}m';
}
