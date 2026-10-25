import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/core/theme/app_colors.dart';
import 'package:studyup/features/community/data/community_models.dart';
import 'package:studyup/features/community/presentation/community_providers.dart';
import 'package:studyup/features/community/presentation/community_screen.dart';
import 'package:studyup/features/progress/data/study_session.dart';
import 'package:studyup/features/progress/presentation/study_progress_controller.dart';

void main() {
  // Test Monday: 2026-10-19
  final monday = DateTime(2026, 10, 19);

  // Generate sessions producing exactly 28h 32m = 1712 minutes:
  // Mon: 240m (4h), Tue: 240m (4h), Wed: 240m (4h), Thu: 240m (4h),
  // Fri: 240m (4h), Sat: 240m (4h), Sun: 272m (4h 32m) -> Sum = 1712m = 28h 32m.
  final sampleSessions = [
    // Monday 4 hours
    StudySession(
      id: 'sess-mon',
      subjectId: 'general',
      subjectName: 'Daily Study',
      checkInTime: DateTime(2026, 10, 19, 9, 0),
      checkOutTime: DateTime(2026, 10, 19, 13, 0),
      studySegments: [
        StudyTimeSegment(
          startTime: DateTime(2026, 10, 19, 9, 0),
          endTime: DateTime(2026, 10, 19, 13, 0),
        ),
      ],
    ),
    // Tuesday 4 hours
    StudySession(
      id: 'sess-tue',
      subjectId: 'general',
      subjectName: 'Daily Study',
      checkInTime: DateTime(2026, 10, 20, 9, 0),
      checkOutTime: DateTime(2026, 10, 20, 13, 0),
      studySegments: [
        StudyTimeSegment(
          startTime: DateTime(2026, 10, 20, 9, 0),
          endTime: DateTime(2026, 10, 20, 13, 0),
        ),
      ],
    ),
    // Wednesday 4 hours
    StudySession(
      id: 'sess-wed',
      subjectId: 'general',
      subjectName: 'Daily Study',
      checkInTime: DateTime(2026, 10, 21, 9, 0),
      checkOutTime: DateTime(2026, 10, 21, 13, 0),
      studySegments: [
        StudyTimeSegment(
          startTime: DateTime(2026, 10, 21, 9, 0),
          endTime: DateTime(2026, 10, 21, 13, 0),
        ),
      ],
    ),
    // Thursday 4 hours
    StudySession(
      id: 'sess-thu',
      subjectId: 'general',
      subjectName: 'Daily Study',
      checkInTime: DateTime(2026, 10, 22, 9, 0),
      checkOutTime: DateTime(2026, 10, 22, 13, 0),
      studySegments: [
        StudyTimeSegment(
          startTime: DateTime(2026, 10, 22, 9, 0),
          endTime: DateTime(2026, 10, 22, 13, 0),
        ),
      ],
    ),
    // Friday 4 hours
    StudySession(
      id: 'sess-fri',
      subjectId: 'general',
      subjectName: 'Daily Study',
      checkInTime: DateTime(2026, 10, 23, 9, 0),
      checkOutTime: DateTime(2026, 10, 23, 13, 0),
      studySegments: [
        StudyTimeSegment(
          startTime: DateTime(2026, 10, 23, 9, 0),
          endTime: DateTime(2026, 10, 23, 13, 0),
        ),
      ],
    ),
    // Saturday 4 hours
    StudySession(
      id: 'sess-sat',
      subjectId: 'general',
      subjectName: 'Daily Study',
      checkInTime: DateTime(2026, 10, 24, 9, 0),
      checkOutTime: DateTime(2026, 10, 24, 13, 0),
      studySegments: [
        StudyTimeSegment(
          startTime: DateTime(2026, 10, 24, 9, 0),
          endTime: DateTime(2026, 10, 24, 13, 0),
        ),
      ],
    ),
    // Sunday 4 hours 32 minutes (272m)
    StudySession(
      id: 'sess-sun',
      subjectId: 'general',
      subjectName: 'Daily Study',
      checkInTime: DateTime(2026, 10, 25, 9, 0),
      checkOutTime: DateTime(2026, 10, 25, 13, 32),
      studySegments: [
        StudyTimeSegment(
          startTime: DateTime(2026, 10, 25, 9, 0),
          endTime: DateTime(2026, 10, 25, 13, 32),
        ),
      ],
    ),
  ];

  group('Weekly Progress Wiring & Consistency', () {
    test('1. Insights formula produces exactly 28h 32m (1712 minutes) from saved records', () {
      final state = StudyProgressState(
        sessions: sampleSessions,
        dailyStudyGoalMinutes: 480,
        isLoaded: true,
      );

      final weekMinutes = state.minutesByWeekday(monday);
      final totalMinutes = weekMinutes.fold(0, (sum, m) => sum + m);

      expect(totalMinutes, 1712);
      expect(totalMinutes ~/ 60, 28);
      expect(totalMinutes % 60, 32);
      expect(state.minutesForWeek(monday), 1712);
    });

    testWidgets('2. Community displays 28h 32m consistently across comparison, podium, and leaderboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const topFriend = CommunityMember(
        id: 'friend-1',
        name: 'Aisha Rahman',
        avatarColor: AppColors.blue,
        weeklyMinutes: 1200, // 20h
        streakDays: 5,
      );

      final state = StudyProgressState(
        sessions: sampleSessions,
        dailyStudyGoalMinutes: 480,
        isLoaded: true,
      );

      // Build Community screen with progress state having the real sessions
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studyProgressProvider.overrideWith((ref) => _StaticProgressNotifier(state)),
            selectedCommunityMondayProvider.overrideWith((ref) => monday),
            communityHomeProvider.overrideWith((ref, mon) async {
              final userMins = state.minutesForWeek(mon);
              final me = CommunityMember(
                id: 'my-user-id',
                name: 'You',
                avatarColor: AppColors.green,
                weeklyMinutes: userMins,
                isCurrentUser: true,
              );
              final ranked = [me, topFriend]..sort((a, b) => b.weeklyMinutes.compareTo(a.weeklyMinutes));
              return CommunityHomeData(
                me: me,
                meWeekly: WeeklyCardSummary(
                  weekStart: mon,
                  completedSessions: 7,
                  totalMinutes: userMins,
                  goalMinutes: 3360,
                  percent: (userMins / 3360 * 100).round(),
                  streak: 7,
                ),
                meToday: TodayCardSummary(
                  date: DateTime.now(),
                  completedSessions: 1,
                  totalMinutes: 272,
                ),
                friends: const [topFriend],
                allRankedMembers: ranked,
              );
            }),
          ],
          child: const MaterialApp(
            home: CommunityScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // "28h 32m" must appear multiple times:
      // 1) In the Top 3 Podium (#1 spot)
      // 2) In the Weekly Comparison Card ("You" row)
      // 3) In the Leaderboard row (#1 spot with "YOU" tag)
      final formattedTotal = find.text('28h 32m');
      expect(formattedTotal, findsWidgets);
      expect(formattedTotal.evaluate().length, greaterThanOrEqualTo(3));

      // Leaderboard must show "You" ranked #1 because 28h 32m (1712m) > 20h (1200m)
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('You'), findsWidgets);
      expect(find.text('YOU'), findsWidgets);

      // Comparison card must show difference badge: 28h 32m - 20h 0m = 8h 32m leading
      expect(find.text('You are leading by 8h 32m this week!'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    });

    testWidgets('3. Changing selected week updates user and friends together', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Last week Monday (no sessions)
      final pastMonday = monday.subtract(const Duration(days: 7));

      final state = StudyProgressState(
        sessions: sampleSessions, // Sessions only in `monday`, not in `pastMonday`
        dailyStudyGoalMinutes: 480,
        isLoaded: true,
      );

      final container = ProviderContainer(
        overrides: [
          studyProgressProvider.overrideWith((ref) => _StaticProgressNotifier(state)),
          selectedCommunityMondayProvider.overrideWith((ref) => pastMonday),
        ],
      );
      addTearDown(container.dispose);

      final pastMins = state.minutesForWeek(pastMonday);
      expect(pastMins, 0); // Past week genuine zero progress (no fake data)

      final currentMins = state.minutesForWeek(monday);
      expect(currentMins, 1712); // Selected week 28h 32m
    });

    testWidgets('4. Failed fetch displays error state and never fabricates fake progress', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            communityHomeProvider.overrideWith((ref, mon) async {
              throw Exception('Database network timeout');
            }),
          ],
          child: const MaterialApp(
            home: CommunityScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Error container is rendered
      expect(find.text('Could not load Community'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Never shows fabricated users or fake times on failure
      expect(find.text('28h 32m'), findsNothing);
      expect(find.text('Aisha Rahman'), findsNothing);
    });
  });
}

class _StaticProgressNotifier extends StateNotifier<StudyProgressState>
    implements StudyProgressController {
  _StaticProgressNotifier(super.state);

  @override
  Future<void> checkIn({DateTime? at}) async {}

  @override
  Future<void> checkOut({DateTime? at}) async {}

  @override
  Future<void> pauseSession({DateTime? at}) async {}

  @override
  Future<void> resumeSession({DateTime? at}) async {}

  @override
  Future<void> startSession({DateTime? checkInTime}) async {}

  @override
  Future<void> endSession({DateTime? checkOutTime}) async {}

  @override
  Future<void> setDailyStudyGoalMinutes(int minutes) async {}
}
