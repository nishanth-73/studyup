import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';
import 'package:studyup/features/progress/presentation/study_progress_controller.dart';
import 'package:studyup/features/social/data/social_providers.dart';
import 'package:studyup/features/social/data/social_remote.dart';

/// Two-account Community reproduction: A invites, B accepts, then BOTH
/// boards must show the other person.
///
/// The fake server mirrors the deployed SQL semantics exactly:
///   friendships  -> one row per pair (user_low, user_high), PK on the
///                   unordered pair, so membership is symmetric;
///   my_friends()  -> every profile the viewer is friends with;
///   leaderboard_scope('friends') -> friends (+ self), aggregates only,
///                   missing rows mean ZERO, never absence.
class _Profile {
  _Profile(
    this.id,
    this.displayName, {
    this.avatarId = 'robo-default',
    this.blobVariant = 0,
    this.leaderboardOptIn = true,
  });

  final String id;
  final String displayName;
  final String avatarId;
  final int blobVariant;
  final bool leaderboardOptIn;
}

class _FakeServer {
  final profiles = <String, _Profile>{};
  final weekSeconds = <String, int>{};
  final totalSeconds = <String, int>{};
  final friendships = <String>{};
  final invitations = <String, String>{}; // token -> inviter id
  final accepted = <String>{};
  final realtimeListeners = <void Function()>[];

  void addUser(_Profile p) => profiles[p.id] = p;

  static String pair(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

  bool areFriends(String a, String b) => friendships.contains(pair(a, b));

  String createInvitation(String inviter) {
    final token = 'tok-${invitations.length + 1}';
    invitations[token] = inviter;
    return token;
  }

  InvitePreview preview(String token) {
    final inviter = invitations[token];
    if (inviter == null) {
      return const InvitePreview(
        displayName: '',
        avatarId: '',
        valid: false,
        reason: 'invalid',
      );
    }
    if (accepted.contains(token)) {
      return InvitePreview(
        displayName: profiles[inviter]!.displayName,
        avatarId: profiles[inviter]!.avatarId,
        valid: false,
        reason: 'accepted',
      );
    }
    final p = profiles[inviter]!;
    return InvitePreview(
      displayName: p.displayName,
      avatarId: p.avatarId,
      valid: true,
      reason: 'ok',
    );
  }

  /// Mirrors accept_invitation(): validates, then inserts ONE canonical
  /// friendship row. Repeat taps raise instead of duplicating.
  String accept(String token, String viewer) {
    final inviter = invitations[token];
    if (inviter == null) throw StateError('invalid token');
    if (accepted.contains(token)) throw StateError('already accepted');
    if (inviter == viewer) throw StateError('self invite');
    accepted.add(token);
    friendships.add(pair(viewer, inviter));
    for (final cb in realtimeListeners) {
      cb();
    }
    return profiles[inviter]!.displayName;
  }

  List<RemoteFriend> friendsOf(String viewer) => [
    for (final p in profiles.values)
      if (areFriends(viewer, p.id))
        RemoteFriend(
          userId: p.id,
          displayName: p.displayName,
          avatarId: p.avatarId,
          blobVariant: p.blobVariant,
          leaderboardOptIn: p.leaderboardOptIn,
        ),
  ]..sort((a, b) => a.displayName.compareTo(b.displayName));

  List<RemoteBoardRow> boardOf(String viewer) => [
    for (final p in profiles.values)
      if (p.leaderboardOptIn && (p.id == viewer || areFriends(viewer, p.id)))
        RemoteBoardRow(
          userId: p.id,
          displayName: p.displayName,
          avatarId: p.avatarId,
          blobVariant: p.blobVariant,
          weekSeconds: weekSeconds[p.id] ?? 0,
          activeDays: 0,
          totalSeconds: totalSeconds[p.id] ?? 0,
          streakDays: 0,
        ),
  ];
}

/// A [SocialRemote] bound to one account against the shared fake server.
class _ViewerRemote extends SocialRemote {
  _ViewerRemote(this.server, this.viewer)
    : client = SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
      super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final SupabaseClient client;
  final _FakeServer server;
  final String viewer;
  int acceptCalls = 0;

  @override
  Future<InvitePreview> previewInvitation(String rawToken) async =>
      server.preview(rawToken);

  @override
  Future<String> acceptInvitation(String rawToken) async {
    acceptCalls++;
    return server.accept(rawToken, viewer);
  }

  @override
  Future<String> createInvitation({int validDays = 7}) async =>
      server.createInvitation(viewer);

  @override
  Future<List<RemoteFriend>> myFriends() async => server.friendsOf(viewer);

  @override
  Future<List<RemoteBoardRow>> leaderboard({
    required DateTime weekStart,
  }) async => server.boardOf(viewer);

  @override
  RealtimeChannel subscribeFriendships(void Function() onChange) {
    server.realtimeListeners.add(onChange);
    return client.channel('friendships-${viewer.hashCode}');
  }

  @override
  RealtimeChannel subscribeIncomingRequests(void Function() onChange) =>
      client.channel('requests-${viewer.hashCode}');
}

DateTime mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

ProviderContainer _viewerContainer(_ViewerRemote remote, String viewerId) {
  return ProviderContainer(
    overrides: [
      socialLiveProvider.overrideWithValue(true),
      backendUserIdProvider.overrideWithValue(viewerId),
      socialRemoteProvider.overrideWithValue(remote),
    ],
  );
}

void main() {
  Future<void> ready(ProviderContainer container) async {
    container.listen(studyProgressProvider, (_, _) {});
    for (var i = 0; i < 200; i++) {
      if (container.read(studyProgressProvider).isLoaded) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('A invites, B accepts: BOTH boards show the other person', () async {
    SharedPreferences.setMockInitialValues({});
    final server = _FakeServer()
      ..addUser(_Profile('A', 'Alice', avatarId: 'avatar-a', blobVariant: 1))
      ..addUser(_Profile('B', 'Bob', avatarId: 'avatar-b', blobVariant: 2));
    final week = mondayOf(DateTime.now());

    final alice = _ViewerRemote(server, 'A');
    final bob = _ViewerRemote(server, 'B');
    final aliceContainer = _viewerContainer(alice, 'A');
    final bobContainer = _viewerContainer(bob, 'B');
    addTearDown(aliceContainer.dispose);
    addTearDown(bobContainer.dispose);
    await ready(aliceContainer);
    await ready(bobContainer);

    // 1. A sends an invitation.
    final token = await alice.createInvitation();
    expect(server.invitations[token], 'A');

    // 2. B opens the link and previews it.
    final preview = await bob.previewInvitation(token);
    expect(preview.valid, isTrue);
    expect(preview.displayName, 'Alice');

    // 3. B accepts → the server creates the mutual friendship.
    final inviterName = await bob.acceptInvitation(token);
    expect(inviterName, 'Alice');
    expect(server.areFriends('A', 'B'), isTrue);
    expect(server.areFriends('B', 'A'), isTrue, reason: 'friendship is mutual');

    // 4. The receiver (B) sees the sender (A) — real name/avatar.
    final bEntries = await bobContainer.read(
      communityDisplayProvider(week).future,
    );
    final aOnB = bEntries.where((e) => e.memberId == 'A').toList();
    expect(aOnB, hasLength(1), reason: 'receiver must see the sender');
    expect(aOnB.single.displayName, 'Alice');
    expect(aOnB.single.avatarId, 'avatar-a');
    expect(aOnB.single.blobVariant, 1);
    expect(aOnB.single.isSelf, isFalse);

    // 5. The sender (A) sees the receiver (B).
    final aEntries = await aliceContainer.read(
      communityDisplayProvider(week).future,
    );
    final bOnA = aEntries.where((e) => e.memberId == 'B').toList();
    expect(bOnA, hasLength(1), reason: 'sender must see the receiver');
    expect(bOnA.single.displayName, 'Bob');
    expect(bOnA.single.avatarId, 'avatar-b');
    expect(bOnA.single.isSelf, isFalse);

    // Each account sees ITSELF as self, exactly once.
    expect(bEntries.where((e) => e.isSelf).single.memberId, 'B');
    expect(aEntries.where((e) => e.isSelf).single.memberId, 'A');
  });

  test('both boards show the friend with zero progress (test 6)', () async {
    SharedPreferences.setMockInitialValues({});
    final server = _FakeServer()
      ..addUser(_Profile('A', 'Alice', avatarId: 'avatar-a'))
      ..addUser(_Profile('B', 'Bob', avatarId: 'avatar-b'));
    final week = mondayOf(DateTime.now());
    final alice = _ViewerRemote(server, 'A');
    final bob = _ViewerRemote(server, 'B');
    final bobContainer = _viewerContainer(bob, 'B');
    final aliceContainer = _viewerContainer(alice, 'A');
    addTearDown(bobContainer.dispose);
    addTearDown(aliceContainer.dispose);
    await ready(bobContainer);
    await ready(aliceContainer);

    final token = await alice.createInvitation();
    await bob.acceptInvitation(token);
    // Nobody has studied: zero XP, zero seconds, zero streak, level 1.
    expect(server.weekSeconds, isEmpty);

    for (final pair in [(bobContainer, 'B'), (aliceContainer, 'A')]) {
      final container = pair.$1;
      final who = pair.$2;
      final entries = await container.read(
        communityDisplayProvider(week).future,
      );
      final other = entries.where((e) => e.memberId != who).toList();
      expect(other, hasLength(1), reason: '$who must see the friend');
      expect(other.single.weekSeconds, 0);
      expect(other.single.hasData, isFalse, reason: 'no data, not missing');
      expect(other.single.level, 1);
    }
  });

  test('a friend who opted out of the leaderboard is still a friend', () async {
    SharedPreferences.setMockInitialValues({});
    final server = _FakeServer()
      // Alice shares no leaderboard totals, Bob does.
      ..addUser(
        _Profile('A', 'Alice', avatarId: 'avatar-a', leaderboardOptIn: false),
      )
      ..addUser(_Profile('B', 'Bob', avatarId: 'avatar-b'));
    final week = mondayOf(DateTime.now());
    final alice = _ViewerRemote(server, 'A');
    final bob = _ViewerRemote(server, 'B');
    final bobContainer = _viewerContainer(bob, 'B');
    addTearDown(bobContainer.dispose);
    await ready(bobContainer);

    final token = await alice.createInvitation();
    await bob.acceptInvitation(token);

    final entries = await bobContainer.read(
      communityDisplayProvider(week).future,
    );
    // Friendship is membership: Alice is still listed, with honest zeros,
    // and never with invented progress.
    final aliceRow = entries.where((e) => e.memberId == 'A').toList();
    expect(aliceRow, hasLength(1));
    expect(aliceRow.single.displayName, 'Alice');
    expect(aliceRow.single.weekSeconds, 0);
    expect(aliceRow.single.hasData, isFalse);
  });

  test('the sender refreshes when the friendship is created (realtime)', () async {
    SharedPreferences.setMockInitialValues({});
    final server = _FakeServer()
      ..addUser(_Profile('A', 'Alice', avatarId: 'avatar-a'))
      ..addUser(_Profile('B', 'Bob', avatarId: 'avatar-b'));
    final week = mondayOf(DateTime.now());
    final alice = _ViewerRemote(server, 'A');
    final bob = _ViewerRemote(server, 'B');
    final aliceContainer = _viewerContainer(alice, 'A');
    addTearDown(aliceContainer.dispose);
    await ready(aliceContainer);

    // A's Community tab is open, subscribed to friendship changes.
    aliceContainer.listen(remoteRealtimeProvider, (_, _) {});
    expect(server.realtimeListeners, isNotEmpty);

    var entries = await aliceContainer.read(
      communityDisplayProvider(week).future,
    );
    expect(entries.where((e) => e.memberId == 'B'), isEmpty);

    // B accepts on the other device: the friendship event fires here.
    final token = await alice.createInvitation();
    await bob.acceptInvitation(token);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    entries = await aliceContainer.read(communityDisplayProvider(week).future);
    final friend = entries.where((e) => e.memberId == 'B').toList();
    expect(friend, hasLength(1));
    expect(friend.single.displayName, 'Bob');
    expect(friend.single.avatarId, 'avatar-b');
  });

  test('repeated taps never duplicate the friendship (idempotent)', () async {
    SharedPreferences.setMockInitialValues({});
    final server = _FakeServer()
      ..addUser(_Profile('A', 'Alice'))
      ..addUser(_Profile('B', 'Bob'));
    final week = mondayOf(DateTime.now());
    final alice = _ViewerRemote(server, 'A');
    final bob = _ViewerRemote(server, 'B');
    final bobContainer = _viewerContainer(bob, 'B');
    addTearDown(bobContainer.dispose);
    await ready(bobContainer);

    final token = await alice.createInvitation();
    await bob.acceptInvitation(token);
    expect(bob.acceptCalls, 1);

    // Second tap on the same link: the server refuses, no second row.
    await expectLater(
      bob.acceptInvitation(token),
      throwsA(isA<StateError>()),
    );
    expect(bob.acceptCalls, 2, reason: 'the attempt was made, not silently skipped');
    expect(
      server.friendships.where((p) => p == _FakeServer.pair('A', 'B')).length,
      1,
    );

    final entries = await bobContainer.read(
      communityDisplayProvider(week).future,
    );
    expect(entries.where((e) => e.memberId == 'A'), hasLength(1));
  });

  test('ranking uses real data only (no invented progress)', () async {
    SharedPreferences.setMockInitialValues({});
    final server = _FakeServer()
      ..addUser(_Profile('A', 'Alice'))
      ..addUser(_Profile('B', 'Bob'));
    final week = mondayOf(DateTime.now());
    final alice = _ViewerRemote(server, 'A');
    final bob = _ViewerRemote(server, 'B');
    final aliceContainer = _viewerContainer(alice, 'A');
    addTearDown(aliceContainer.dispose);
    await ready(aliceContainer);

    final token = await alice.createInvitation();
    await bob.acceptInvitation(token);
    // Bob has real study time this week; Alice has none.
    server.weekSeconds['B'] = 7200;

    final entries = await aliceContainer.read(
      communityDisplayProvider(week).future,
    );
    final bobRow = entries.firstWhere((e) => e.memberId == 'B');
    expect(bobRow.weekSeconds, 7200);
    expect(bobRow.hasData, isTrue);
    expect(bobRow.rank, 1, reason: 'the only member with data ranks first');
    // Self stays on the board as "You" with honest zeros (live local data,
    // never invented progress) — it is the one member that is always ranked.
    final aliceRow = entries.firstWhere((e) => e.memberId == 'A');
    expect(aliceRow.isSelf, isTrue);
    expect(aliceRow.weekSeconds, 0);
    expect(aliceRow.rank, 2);
    // No other members exist: nothing was fabricated.
    expect(entries, hasLength(2));
  });
}