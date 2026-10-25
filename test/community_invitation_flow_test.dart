import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:studyup/core/theme/app_colors.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';
import 'package:studyup/features/avatar/data/user_profile.dart';
import 'package:studyup/features/avatar/presentation/user_profile_controller.dart';
import 'package:studyup/features/community/data/community_models.dart';
import 'package:studyup/features/community/data/community_repository.dart';
import 'package:studyup/features/community/data/invitation_link_service.dart';
import 'package:studyup/features/community/presentation/community_providers.dart';
import 'package:studyup/features/community/presentation/community_screen.dart';
import 'package:studyup/features/progress/presentation/study_progress_controller.dart';

class _FakeCommunityRepo implements CommunityRepository {
  String acceptResult = 'ok';
  String? lastAcceptedToken;
  InvitePreviewData previewToReturn = const InvitePreviewData(
    status: 'valid',
    inviterName: 'Maya Lin',
    currentWeekPercent: 65,
  );

  @override
  String? get currentUserId => 'user-me';

  @override
  Future<CommunityHomeData> getCommunityHome(DateTime monday) async {
    final meWeekly = WeeklyCardSummary(
      weekStart: monday,
      completedSessions: 5,
      totalMinutes: 300,
      goalMinutes: 600,
      percent: 50,
      streak: 3,
    );
    final me = CommunityMember(
      id: 'user-me',
      name: 'You',
      avatarUrl: null,
      avatarColor: AppColors.green,
      weeklyMinutes: 300,
      percent: 50,
      completedSessions: 5,
      streakDays: 3,
      isCurrentUser: true,
    );
    return CommunityHomeData(
      me: me,
      meWeekly: meWeekly,
      meToday: TodayCardSummary(
        date: DateTime.now(),
        completedSessions: 1,
        totalMinutes: 60,
      ),
      friends: [],
      allRankedMembers: [me],
    );
  }

  @override
  Future<InvitePreviewData> getInvitePreview(String token) async {
    return previewToReturn;
  }

  @override
  Future<String> acceptInvite(String token) async {
    lastAcceptedToken = token;
    return acceptResult;
  }

  @override
  Future<String> createInviteLink() async {
    return 'https://studyup-4x7z.vercel.app/invite/fake-created-token';
  }

  @override
  Future<WeekDetailSummary> getWeekDetail(String userId, DateTime monday) async {
    throw UnimplementedError();
  }

  @override
  RealtimeChannel subscribeToPings(void Function() onPing) {
    return RealtimeChannel('test', RealtimeClient('http://localhost'));
  }
}

class _StaticProgressNotifier extends StateNotifier<StudyProgressState>
    implements StudyProgressController {
  _StaticProgressNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StaticProfileController
    extends StateNotifier<AsyncValue<UserProfile?>>
    implements UserProfileController {
  _StaticProfileController(UserProfile? profile)
      : super(AsyncValue.data(profile));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Friend Invitation Flow & Deep Linking', () {
    test('1. extractInviteToken parses supported formats and rejects invalid ones', () {
      // 1. Web invite URLs (/invite/ and /i/)
      expect(
        extractInviteToken(Uri.parse('https://studyup-4x7z.vercel.app/invite/abc123XYZ_')),
        'abc123XYZ_',
      );
      expect(
        extractInviteToken(Uri.parse('https://studyup-4x7z.vercel.app/i/abc123XYZ_')),
        'abc123XYZ_',
      );
      expect(
        extractInviteToken(Uri.parse('https://invite.studyup.app/invite/sec-token-9988')),
        'sec-token-9988',
      );

      // 2. Custom app scheme (studyup://invite/<token> and studyup://i/<token>)
      expect(
        extractInviteToken(Uri.parse('studyup://invite/custom-tok-1234')),
        'custom-tok-1234',
      );
      expect(
        extractInviteToken(Uri.parse('studyup://i/custom-tok-5678')),
        'custom-tok-5678',
      );

      // 3. Query parameter format (?token=...)
      expect(
        extractInviteToken(Uri.parse('https://studyup-4x7z.vercel.app/community?token=query-tok-4455')),
        'query-tok-4455',
      );

      // 4. Invalid / malformed tokens rejected (< 8 chars, invalid characters, null)
      expect(extractInviteToken(null), isNull);
      expect(extractInviteToken(Uri.parse('https://studyup-4x7z.vercel.app/home')), isNull);
      expect(extractInviteToken(Uri.parse('https://studyup-4x7z.vercel.app/invite/short')), isNull);
      expect(extractInviteToken(Uri.parse('https://studyup-4x7z.vercel.app/invite/bad*token!')), isNull);
    });

    testWidgets('2. CommunityScreen displays invitation acceptance card when pendingInviteToken is present', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = _FakeCommunityRepo();
      fakeRepo.previewToReturn = const InvitePreviewData(
        status: 'valid',
        inviterName: 'Maya Lin',
        currentWeekPercent: 75,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            communityRepositoryProvider.overrideWithValue(fakeRepo),
            studyProgressProvider.overrideWith((ref) => _StaticProgressNotifier(
                  const StudyProgressState(sessions: [], dailyStudyGoalMinutes: 60, isLoaded: true),
                )),
            userProfileProvider.overrideWith(
              (ref) => _StaticProfileController(
                const UserProfile(
                  displayName: 'You',
                  blobName: 'Robo',
                  avatarId: '1',
                  slidesSeen: true,
                  setupComplete: true,
                ),
              ),
            ),
            backendUserIdProvider.overrideWith((ref) => 'user-me'),
            pendingInviteTokenProvider.overrideWith((ref) {
              final notifier = PendingInviteTokenNotifier();
              notifier.setToken('valid-token-1234', navigate: false);
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CommunityScreen()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the Invitation Acceptance Card is prominently displayed
      expect(find.text('STUDY CIRCLE INVITATION'), findsOneWidget);
      expect(find.text('Maya Lin'), findsWidgets);
      expect(
        find.text('Maya Lin wants to connect with you on StudyUP so you can compare study progress and keep each other going.'),
        findsOneWidget,
      );
      expect(find.text('Accept Invitation'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('3. Accepting invitation calls backend RPC, clears token, and displays confirmation', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = _FakeCommunityRepo();
      fakeRepo.acceptResult = 'ok';

      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            communityRepositoryProvider.overrideWithValue(fakeRepo),
            studyProgressProvider.overrideWith((ref) => _StaticProgressNotifier(
                  const StudyProgressState(sessions: [], dailyStudyGoalMinutes: 60, isLoaded: true),
                )),
            userProfileProvider.overrideWith(
              (ref) => _StaticProfileController(
                const UserProfile(
                  displayName: 'You',
                  blobName: 'Robo',
                  avatarId: '1',
                  slidesSeen: true,
                  setupComplete: true,
                ),
              ),
            ),
            backendUserIdProvider.overrideWith((ref) => 'user-me'),
            pendingInviteTokenProvider.overrideWith((ref) {
              final notifier = PendingInviteTokenNotifier();
              notifier.setToken('token-to-accept-123', navigate: false);
              return notifier;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  capturedRef = ref;
                  return const CommunityScreen();
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Accept Invitation
      final acceptBtn = find.text('Accept Invitation');
      expect(acceptBtn, findsOneWidget);
      await tester.tap(acceptBtn);
      await tester.pumpAndSettle();

      // Verified backend RPC was invoked with token
      expect(fakeRepo.lastAcceptedToken, 'token-to-accept-123');

      // Verified pending token is cleared
      expect(capturedRef.read(pendingInviteTokenProvider), isNull);

      // Verified success snackbar displayed
      expect(find.text('You and Maya Lin are now study friends!'), findsOneWidget);
    });

    testWidgets('4. Unauthenticated user tapping Accept is prompted to sign in and token is preserved', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = _FakeCommunityRepo();
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            communityRepositoryProvider.overrideWithValue(fakeRepo),
            studyProgressProvider.overrideWith((ref) => _StaticProgressNotifier(
                  const StudyProgressState(sessions: [], dailyStudyGoalMinutes: 60, isLoaded: true),
                )),
            userProfileProvider.overrideWith(
              (ref) => _StaticProfileController(
                const UserProfile(
                  displayName: 'Guest',
                  blobName: 'Robo',
                  avatarId: '1',
                  slidesSeen: true,
                  setupComplete: true,
                ),
              ),
            ),
            // Unauthenticated: no backend user id
            backendUserIdProvider.overrideWith((ref) => null),
            pendingInviteTokenProvider.overrideWith((ref) {
              final notifier = PendingInviteTokenNotifier();
              notifier.setToken('saved-token-while-logged-out', navigate: false);
              return notifier;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  capturedRef = ref;
                  return const CommunityScreen();
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final acceptBtn = find.text('Accept Invitation');
      expect(acceptBtn, findsOneWidget);
      await tester.tap(acceptBtn);
      await tester.pump();

      // Verified auth prompt snackbar appears
      expect(find.text('Please sign in to connect with Maya Lin.'), findsOneWidget);

      // Verified token is NOT lost, remains intact to resume after login!
      expect(capturedRef.read(pendingInviteTokenProvider), 'saved-token-while-logged-out');
    });

    testWidgets('5. Self-invites and duplicate friendships display appropriate feedback and clear token', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = _FakeCommunityRepo();
      fakeRepo.acceptResult = 'own'; // Self-invite response from backend

      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            communityRepositoryProvider.overrideWithValue(fakeRepo),
            studyProgressProvider.overrideWith((ref) => _StaticProgressNotifier(
                  const StudyProgressState(sessions: [], dailyStudyGoalMinutes: 60, isLoaded: true),
                )),
            userProfileProvider.overrideWith(
              (ref) => _StaticProfileController(
                const UserProfile(
                  displayName: 'You',
                  blobName: 'Robo',
                  avatarId: '1',
                  slidesSeen: true,
                  setupComplete: true,
                ),
              ),
            ),
            backendUserIdProvider.overrideWith((ref) => 'user-me'),
            pendingInviteTokenProvider.overrideWith((ref) {
              final notifier = PendingInviteTokenNotifier();
              notifier.setToken('self-token-12345', navigate: false);
              return notifier;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  capturedRef = ref;
                  return const CommunityScreen();
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Accept Invitation'));
      await tester.pumpAndSettle();

      expect(find.text('You cannot accept your own invitation link.'), findsOneWidget);
      expect(capturedRef.read(pendingInviteTokenProvider), isNull);
    });

    testWidgets('6. Expired, used, and invalid invites display informative state', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = _FakeCommunityRepo();
      fakeRepo.previewToReturn = const InvitePreviewData(
        status: 'expired',
        inviterName: 'Alex',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            communityRepositoryProvider.overrideWithValue(fakeRepo),
            studyProgressProvider.overrideWith((ref) => _StaticProgressNotifier(
                  const StudyProgressState(sessions: [], dailyStudyGoalMinutes: 60, isLoaded: true),
                )),
            userProfileProvider.overrideWith(
              (ref) => _StaticProfileController(
                const UserProfile(
                  displayName: 'You',
                  blobName: 'Robo',
                  avatarId: '1',
                  slidesSeen: true,
                  setupComplete: true,
                ),
              ),
            ),
            backendUserIdProvider.overrideWith((ref) => 'user-me'),
            pendingInviteTokenProvider.overrideWith((ref) {
              final notifier = PendingInviteTokenNotifier();
              notifier.setToken('expired-tok-1234', navigate: false);
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CommunityScreen()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('This invitation link has expired.'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
    });
  });
}
