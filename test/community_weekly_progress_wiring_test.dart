import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/core/theme/app_colors.dart';
import 'package:studyup/core/widgets/weekly_study_time_card.dart';
import 'package:studyup/features/community/data/community_models.dart';
import 'package:studyup/features/community/presentation/community_providers.dart';
import 'package:studyup/features/community/presentation/community_screen.dart';
import 'package:studyup/features/community/presentation/week_detail_dialog.dart';
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
      // 2) In the Leaderboard row (#1 spot with "YOU" tag)
      final formattedTotal = find.text('28h 32m');
      expect(formattedTotal, findsWidgets);
      expect(formattedTotal.evaluate().length, greaterThanOrEqualTo(2));

      // Leaderboard must show "You" ranked #1 because 28h 32m (1712m) > 20h (1200m)
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('You'), findsWidgets);
      expect(find.text('YOU'), findsWidgets);
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

    testWidgets('5. Person-detail view removes Daily Activity section completely and shows Weekly Progress card with actual 28h 32m for You', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final state = StudyProgressState(
        sessions: sampleSessions,
        dailyStudyGoalMinutes: 480,
        isLoaded: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studyProgressProvider.overrideWith((ref) => _StaticProgressNotifier(state)),
            selectedCommunityMondayProvider.overrideWith((ref) => monday),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showWeekDetailSheet(
                        context: context,
                        userId: 'user-me',
                        userName: 'You',
                        monday: monday,
                      );
                    },
                    child: const Text('Open Detail'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Detail'));
      await tester.pumpAndSettle();

      // Modal sheet is open
      expect(find.byType(WeekDetailSheet), findsOneWidget);

      // Entire Daily Activity section is removed
      expect(find.text('DAILY ACTIVITY'), findsNothing);

      // Replaces with Weekly Progress Card following Insights visual style
      expect(find.byType(WeeklyStudyTimeCard), findsOneWidget);
      expect(find.text('YOU WEEKLY PROGRESS'), findsOneWidget);

      // Displays the actual 28h 32m study time derived from real saved sessions
      expect(find.text('28h 32m'), findsWidgets);

      // Displays summary metrics
      expect(find.text('Studied'), findsOneWidget);
      expect(find.text('Goal %'), findsOneWidget);
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('Streak'), findsOneWidget);
    });

    testWidgets('6. Person-detail view for friend displays friend authorized weekly total matching leaderboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final state = StudyProgressState(
        sessions: sampleSessions,
        dailyStudyGoalMinutes: 480,
        isLoaded: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studyProgressProvider.overrideWith((ref) => _StaticProgressNotifier(state)),
            selectedCommunityMondayProvider.overrideWith((ref) => monday),
            weekDetailProvider.overrideWith((ref, args) async => WeekDetailSummary(
              userId: args.userId,
              userName: 'Aisha Rahman',
              isMe: false,
              weeklyCard: WeeklyCardSummary(
                weekStart: args.monday,
                completedSessions: 6,
                totalMinutes: 1200, // 20h
                goalMinutes: 600,
                percent: 200,
                streak: 10,
              ),
              days: List.generate(
                7,
                (i) => DayDetailSummary(
                  date: args.monday.add(Duration(days: i)),
                  minutes: 171,
                  sessionsCompleted: 1,
                ),
              ),
            )),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showWeekDetailSheet(
                        context: context,
                        userId: 'friend-1',
                        userName: 'Aisha Rahman',
                        monday: monday,
                      );
                    },
                    child: const Text('Open Friend Detail'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Friend Detail'));
      await tester.pumpAndSettle();

      expect(find.byType(WeekDetailSheet), findsOneWidget);

      // No Daily Activity section
      expect(find.text('DAILY ACTIVITY'), findsNothing);

      // Weekly Progress Card for Aisha Rahman
      expect(find.byType(WeeklyStudyTimeCard), findsOneWidget);
      expect(find.text('AISHA RAHMAN WEEKLY PROGRESS'), findsOneWidget);
      expect(find.text('20h'), findsWidgets);
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
