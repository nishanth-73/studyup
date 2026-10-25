import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/theme/app_colors.dart';
import 'package:studyup/features/avatar/data/user_profile.dart';
import 'package:studyup/features/avatar/presentation/user_profile_controller.dart';
import 'package:studyup/features/community/data/community_models.dart';
import 'package:studyup/features/community/presentation/community_providers.dart';
import 'package:studyup/features/community/presentation/community_screen.dart';
import 'package:studyup/features/community/presentation/full_leaderboard_screen.dart';
import 'package:studyup/features/progress/presentation/study_progress_controller.dart';

class _FakeProgressNotifier extends StateNotifier<StudyProgressState>
    implements StudyProgressController {
  _FakeProgressNotifier(super.initialState);

  void triggerTick() {
    state = state.copyWith();
  }

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

class _StaticProfileNotifier extends StateNotifier<AsyncValue<UserProfile?>>
    implements UserProfileController {
  _StaticProfileNotifier(UserProfile profile)
      : super(AsyncValue.data(profile));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const testMe = CommunityMember(
    id: 'user-me',
    name: 'Alex',
    avatarColor: AppColors.cta,
    weeklyMinutes: 800,
    isCurrentUser: true,
    streakDays: 5,
  );
  const testFriend1 = CommunityMember(
    id: 'user-1',
    name: 'Aisha Rahman',
    avatarColor: AppColors.primary,
    weeklyMinutes: 1200,
    streakDays: 14,
  );
  const testFriend2 = CommunityMember(
    id: 'user-2',
    name: 'Vikram Sharma',
    avatarColor: AppColors.blue,
    weeklyMinutes: 600,
    streakDays: 3,
  );

  final testHomeData = CommunityHomeData(
    me: testMe,
    meWeekly: WeeklyCardSummary(
      weekStart: DateTime(2026, 10, 19),
      completedSessions: 8,
      totalMinutes: 800,
      goalMinutes: 600,
      percent: 133,
      streak: 5,
    ),
    meToday: TodayCardSummary(
      date: DateTime(2026, 10, 24),
      completedSessions: 2,
      totalMinutes: 90,
    ),
    friends: const [testFriend1, testFriend2],
    allRankedMembers: const [testFriend1, testMe, testFriend2],
  );

  testWidgets('FullLeaderboardScreen displays all members, ranking, avatars, and progress bars', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith((ref) => _StaticProfileNotifier(
            const UserProfile(
              displayName: 'Alex',
              blobName: 'Robo',
              avatarId: 'student_boy',
            ),
          )),
        ],
        child: MaterialApp(
          home: FullLeaderboardScreen(
            members: [testFriend1, testMe, testFriend2],
            weekLabel: 'This week',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Ranks #1, #2, #3
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);

    // Names
    expect(find.text('Aisha Rahman'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Vikram Sharma'), findsOneWidget);

    // "YOU" pill for current user
    expect(find.text('YOU'), findsOneWidget);

    // Formatted times (1200m -> 20h, 800m -> 13h 20m, 600m -> 10h)
    expect(find.text('20h'), findsOneWidget);
    expect(find.text('13h 20m'), findsOneWidget);
    expect(find.text('10h'), findsOneWidget);

    // Smooth scrollable list
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('CommunityScreen maintains visible content during background refresh without flashing loading spinner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    Completer<CommunityHomeData> completer = Completer<CommunityHomeData>();
    completer.complete(testHomeData);

    final container = ProviderContainer(
      overrides: [
        communityHomeProvider.overrideWith((ref, monday) => completer.future),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: CommunityScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Community data is visible
    expect(find.text('TOP 3 THIS WEEK'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Loading community...'), findsNothing);

    // Start background refresh
    final nextCompleter = Completer<CommunityHomeData>();
    container.updateOverrides([
      communityHomeProvider.overrideWith((ref, monday) => nextCompleter.future),
    ]);
    await tester.pump(); // Frame during active loading

    // Data stays visible! Never flashes loading indicator
    expect(find.text('TOP 3 THIS WEEK'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Loading community...'), findsNothing);

    // Finish reload
    nextCompleter.complete(testHomeData);
    await tester.pumpAndSettle();
    expect(find.text('TOP 3 THIS WEEK'), findsOneWidget);
  });

  testWidgets('Failed background refresh retains visible data with subtle retry banner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    bool shouldFail = false;
    final container = ProviderContainer(
      overrides: [
        communityHomeProvider.overrideWith((ref, monday) async {
          if (shouldFail) {
            throw Exception('Network disconnected');
          }
          return testHomeData;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: CommunityScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Content is visible
    expect(find.text('TOP 3 THIS WEEK'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);

    // Now trigger refresh with network failure
    shouldFail = true;
    final monday = container.read(selectedCommunityMondayProvider);
    container.invalidate(communityHomeProvider(monday));
    await tester.pumpAndSettle();

    // Content stays visible
    expect(find.text('TOP 3 THIS WEEK'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);

    // Subtle retry indicator is displayed instead of blank screen
    expect(find.text('Could not refresh latest stats'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Active ticker state.copyWith ticks do NOT cause rebuild loops in communityHomeProvider', (
    tester,
  ) async {
    final notifier = _FakeProgressNotifier(
      const StudyProgressState(isLoaded: true),
    );

    int communityComputeCount = 0;
    final monday = DateTime(2026, 10, 19);

    final container = ProviderContainer(
      overrides: [
        studyProgressProvider.overrideWith((ref) => notifier),
      ],
    );
    addTearDown(container.dispose);

    // Listen to communityHomeProvider
    container.listen(communityHomeProvider(monday), (previous, next) {
      if (next.hasValue) {
        communityComputeCount++;
      }
    });

    await container.read(communityHomeProvider(monday).future);
    expect(communityComputeCount, 1);

    // Simulate 5 periodic 1-second ticks of an active timer
    notifier.triggerTick();
    notifier.triggerTick();
    notifier.triggerTick();
    notifier.triggerTick();
    notifier.triggerTick();

    // Compute count must REMAIN 1 (no unnecessary re-evaluations or loops!)
    expect(communityComputeCount, 1);
  });
}
