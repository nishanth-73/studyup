import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/community/data/community_models.dart';
import 'package:studyup/features/community/presentation/community_controller.dart';
import 'package:studyup/features/progress/data/study_gamification.dart';
import 'package:studyup/features/progress/data/study_session.dart';

LeaderboardEntry _entry(
  String id, {
  int seconds = 0,
  bool hasData = true,
  bool self = false,
  String name = '',
}) => LeaderboardEntry(
  memberId: id,
  displayName: name.isEmpty ? id : name,
  avatarId: 'robo-default',
  blobVariant: 0,
  isSelf: self,
  weekSeconds: seconds,
  hasData: hasData,
  rank: 0,
);

void main() {
  group('week boundaries', () {
    test('Monday starts its own week', () {
      final monday = DateTime(2026, 10, 12); // a Monday
      expect(mondayOf(monday), DateTime(2026, 10, 12));
      expect(weekKeyFor(monday), '2026-10-12');
    });

    test('weekly seconds clip Monday-to-Monday and merge overlap', () {
      StudySession session(String id, DateTime start, DateTime end) =>
          StudySession(
            id: id,
            subjectId: 'general',
            subjectName: 'Daily Study',
            checkInTime: start,
            checkOutTime: end,
            pausedSeconds: end.difference(start).inSeconds,
            studySegments: [StudyTimeSegment(startTime: start, endTime: end)],
          );

      final weekStart = DateTime(2026, 10, 12);
      final sessions = [
        session(
          'cross-in',
          DateTime(2026, 10, 11, 23, 30),
          DateTime(2026, 10, 12, 0, 30),
        ),
        session('first', DateTime(2026, 10, 12, 9), DateTime(2026, 10, 12, 10)),
        session(
          'overlap',
          DateTime(2026, 10, 12, 9, 30),
          DateTime(2026, 10, 12, 10, 30),
        ),
        session(
          'cross-out',
          DateTime(2026, 10, 18, 23, 30),
          DateTime(2026, 10, 19, 0, 30),
        ),
        session(
          'outside',
          DateTime(2026, 10, 11, 20),
          DateTime(2026, 10, 11, 21),
        ),
      ];

      expect(
        studiedSecondsInRange(
          sessions,
          weekStart,
          weekStart.add(const Duration(days: 7)),
          DateTime(2026, 10, 20),
        ),
        9000,
      );
    });

    test('Sunday belongs to the Monday-start week', () {
      final sunday = DateTime(2026, 10, 18);
      expect(mondayOf(sunday), DateTime(2026, 10, 12));
      expect(weekBounds(sunday).end, DateTime(2026, 10, 19));
    });

    test('month boundary week is consistent', () {
      final jan31 = DateTime(2026, 2, 1); // Sunday
      expect(mondayOf(jan31), DateTime(2026, 1, 26));
      expect(weekKeyFor(jan31), '2026-01-26');
    });
  });

  group('dedupedSeconds', () {
    test('merges overlapping intervals', () {
      final a = DateTime(2026, 10, 12, 9);
      expect(
        dedupedSeconds([
          StudyInterval(a, a.add(const Duration(hours: 2))),
          StudyInterval(
            a.add(const Duration(hours: 1)),
            a.add(const Duration(hours: 3)),
          ),
        ]),
        3 * 3600,
      );
    });

    test('touching intervals merge, disjoint add up', () {
      final a = DateTime(2026, 10, 12, 9);
      expect(
        dedupedSeconds([
          StudyInterval(a, a.add(const Duration(hours: 1))),
          StudyInterval(
            a.add(const Duration(hours: 1)),
            a.add(const Duration(hours: 2)),
          ),
          StudyInterval(
            a.add(const Duration(hours: 5)),
            a.add(const Duration(hours: 6)),
          ),
        ]),
        3 * 3600,
      );
    });

    test('fully contained duplicates do not inflate', () {
      final a = DateTime(2026, 10, 12, 9);
      expect(
        dedupedSeconds([
          StudyInterval(a, a.add(const Duration(hours: 2))),
          StudyInterval(
            a.add(const Duration(minutes: 10)),
            a.add(const Duration(minutes: 20)),
          ),
        ]),
        2 * 3600,
      );
    });
  });

  group('invite codec', () {
    InvitePayload payload(DateTime now) => InvitePayload(
      uid: 'u-alice@example.com',
      name: 'Alice',
      avatarId: 'robo-default',
      blobVariant: 1,
      weekKey: '2026-10-12',
      weekSeconds: 5400,
      issuedAt: now,
    );

    test('round-trips through copy-paste mangling', () {
      final now = DateTime(2026, 10, 15);
      final code = encodeInviteCode(payload(now));
      expect(code.startsWith('SUP1-'), isTrue);
      // Lowercase + spaces (messy chat paste) still decode.
      final back = InviteCodec.decode(
        code.toLowerCase().replaceAll('-', ' '),
        now: now,
      );
      expect(back, isNotNull);
      expect(back!.uid, 'u-alice@example.com');
      expect(back.weekSeconds, 5400);
    });

    test('rejects expired, future, and garbage codes', () {
      final now = DateTime(2026, 10, 15);
      final old = encodeInviteCode(
        payload(now.subtract(const Duration(days: 31))),
      );
      expect(InviteCodec.decode(old, now: now), isNull);
      final future = encodeInviteCode(
        payload(now.add(const Duration(hours: 1))),
      );
      expect(InviteCodec.decode(future, now: now), isNull);
      expect(InviteCodec.decode('SUP1-ZZZZ', now: now), isNull);
      expect(InviteCodec.decode('', now: now), isNull);
    });

    test('v2 codes carry totals and streaks; v1 codes still decode', () {
      final now = DateTime(2026, 10, 15);
      final v2 = InvitePayload(
        uid: 'u-bob',
        name: 'Bob',
        avatarId: 'avatar3',
        blobVariant: 0,
        weekKey: '2026-10-12',
        weekSeconds: 3600,
        issuedAt: now,
        totalSeconds: 7200,
        streakDays: 4,
      );
      final back = InviteCodec.decode(encodeInviteCode(v2), now: now);
      expect(back, isNotNull);
      expect(back!.totalSeconds, 7200);
      expect(back.streakDays, 4);
      // A v1-style payload (no tt/st) decodes with null extras.
      final v1 = InvitePayload(
        uid: 'u-bob',
        name: 'Bob',
        avatarId: 'avatar3',
        blobVariant: 0,
        weekKey: '2026-10-12',
        weekSeconds: 3600,
        issuedAt: now,
      );
      final back1 = InviteCodec.decode(encodeInviteCode(v1), now: now);
      expect(back1, isNotNull);
      expect(back1!.totalSeconds, isNull);
      expect(back1.streakDays, isNull);
    });
  });

  group('friendship rules', () {
    const self = 'u-me';
    const other = 'u-alice';

    FriendRequest pending(String from, String to) => FriendRequest(
      id: 'r1',
      fromId: from,
      fromName: from,
      toId: to,
      createdAt: DateTime(2026, 10, 15),
    );

    test('blocks self-invite, duplicates, and blocked users', () {
      expect(
        FriendshipRules.canSendRequest(
          selfId: self,
          targetId: self,
          friendIds: const [],
          blockedIds: const [],
          blockedByIds: const [],
          openRequests: const [],
        ),
        isNotNull,
      );
      expect(
        FriendshipRules.canSendRequest(
          selfId: self,
          targetId: other,
          friendIds: const [other],
          blockedIds: const [],
          blockedByIds: const [],
          openRequests: const [],
        ),
        isNotNull,
      );
      // Pending in either direction blocks a second request.
      expect(
        FriendshipRules.canSendRequest(
          selfId: self,
          targetId: other,
          friendIds: const [],
          blockedIds: const [],
          blockedByIds: const [],
          openRequests: [pending(self, other)],
        ),
        isNotNull,
      );
      expect(
        FriendshipRules.canSendRequest(
          selfId: self,
          targetId: other,
          friendIds: const [],
          blockedIds: const [],
          blockedByIds: const [],
          openRequests: [pending(other, self)],
        ),
        isNotNull,
      );
      expect(
        FriendshipRules.canSendRequest(
          selfId: self,
          targetId: other,
          friendIds: const [],
          blockedIds: const [other],
          blockedByIds: const [],
          openRequests: const [],
        ),
        isNotNull,
      );
      expect(
        FriendshipRules.canSendRequest(
          selfId: self,
          targetId: other,
          friendIds: const [],
          blockedIds: const [],
          blockedByIds: const [],
          openRequests: const [],
        ),
        isNull,
      );
    });

    test('responses require pending + recipient + not blocked', () {
      final req = pending(other, self);
      expect(
        FriendshipRules.canRespond(
          selfId: self,
          request: req,
          friendIds: const [],
          blockedIds: const [],
        ),
        isNull,
      );
      expect(
        FriendshipRules.canRespond(
          selfId: other, // wrong user
          request: req,
          friendIds: const [],
          blockedIds: const [],
        ),
        isNotNull,
      );
      expect(
        FriendshipRules.canRespond(
          selfId: self,
          request: req,
          friendIds: const [],
          blockedIds: const [other],
        ),
        isNotNull,
      );
    });
  });

  group('leaderboard ranking', () {
    test('orders by time and shares ranks on ties (1,2,2,4)', () {
      final ranked = Leaderboard.rank(
        unordered: [
          _entry('a', seconds: 100),
          _entry('b', seconds: 300),
          _entry('c', seconds: 300),
          _entry('d', seconds: 50),
        ],
        previousRanks: const {},
      );
      expect(ranked.map((e) => e.memberId), ['b', 'c', 'a', 'd']);
      expect(ranked.map((e) => e.rank), [1, 1, 3, 4]);
    });

    test('members without data sort last, unranked', () {
      final ranked = Leaderboard.rank(
        unordered: [_entry('x', hasData: false), _entry('y', seconds: 10)],
        previousRanks: const {},
      );
      expect(ranked.last.memberId, 'x');
      expect(ranked.last.rank, 0);
      expect(ranked.first.rank, 1);
    });

    test('movement needs both weeks', () {
      final ranked = Leaderboard.rank(
        unordered: [_entry('a', seconds: 100), _entry('b', seconds: 200)],
        previousRanks: const {'a': 1},
      );
      final a = ranked.firstWhere((e) => e.memberId == 'a');
      final b = ranked.firstWhere((e) => e.memberId == 'b');
      expect(a.rankMovement, -1); // fell from 1st to 2nd
      expect(b.rankMovement, isNull);
    });
  });

  group('challenge rules + progress', () {
    test('rejects bad ranges and targets', () {
      expect(
        ChallengeRules.validate(
          title: '  ',
          kind: ChallengeGoalKind.hours,
          targetMinutes: 300,
          targetDays: 0,
          startDay: DateTime(2026, 10, 12),
          endDay: DateTime(2026, 10, 19),
        ),
        isNotNull,
      );
      expect(
        ChallengeRules.validate(
          title: 'Week',
          kind: ChallengeGoalKind.days,
          targetMinutes: 0,
          targetDays: 10, // range is 8 days
          startDay: DateTime(2026, 10, 12),
          endDay: DateTime(2026, 10, 19),
        ),
        isNotNull,
      );
      expect(
        ChallengeRules.validate(
          title: 'Week',
          kind: ChallengeGoalKind.days,
          targetMinutes: 0,
          targetDays: 5,
          startDay: DateTime(2026, 10, 12),
          endDay: DateTime(2026, 10, 19),
        ),
        isNull,
      );
    });

    test('progress fractions clamp at 1 and complete at goal', () {
      final hours = Challenge(
        id: 'c',
        title: 'H',
        goalKind: ChallengeGoalKind.hours,
        targetMinutes: 60,
        startDay: DateTime(2026, 10, 12),
        endDay: DateTime(2026, 10, 19),
        ownerId: 'u',
        createdAt: DateTime(2026, 10, 12),
      );
      const over = ChallengeProgress(seconds: 7200, activeDays: 9);
      expect(over.fractionOf(hours), 1.0);
      expect(over.isComplete(hours), isTrue);
      const half = ChallengeProgress(seconds: 1800, activeDays: 2);
      expect(half.fractionOf(hours), 0.5);
    });
  });

  group('room presence', () {
    test('stale heartbeats are never live', () {
      final now = DateTime(2026, 10, 15, 12);
      final fresh = RoomPresence(
        roomId: 'r',
        userId: 'u',
        displayName: 'A',
        joinedAt: now.subtract(const Duration(minutes: 5)),
        lastBeatAt: now.subtract(const Duration(seconds: 119)),
        studying: true,
      );
      final stale = RoomPresence(
        roomId: 'r',
        userId: 'u',
        displayName: 'A',
        joinedAt: now.subtract(const Duration(minutes: 5)),
        lastBeatAt: now.subtract(const Duration(seconds: 121)),
        studying: true,
      );
      expect(fresh.isLiveStudying(now), isTrue);
      expect(stale.isLiveStudying(now), isFalse);
    });
  });

  group('achievements + formatting', () {
    WeeklyRecap recap() => WeeklyRecap(
      weekStart: DateTime(2026, 10, 12),
      totalMinutes: 300,
      previousMinutes: 200,
      studyDays: 5,
      bestDayMinutes: 90,
      hasData: true,
    );

    test('rewards consistency and improvement, not just hours', () {
      final badges = buildAchievements(
        recap: recap(),
        completedChallenge: false,
        bestWeekMinutes: 200,
      );
      final earned = {
        for (final b in badges)
          if (b.earned) b.id,
      };
      expect(earned, containsAll(['steady-5', 'level-up', 'record-week']));
      expect(earned, isNot(contains('perfect-7')));
      expect(earned, isNot(contains('challenger')));
    });

    test('formats hours and minutes', () {
      expect(formatHoursMinutes(2700), '45m');
      expect(formatHoursMinutes(5 * 3600 + 20 * 60), '5h 20m');
    });
  });

  group('podium data (streak + level propagation)', () {
    test('ranked entries keep streak and level', () {
      final ranked = Leaderboard.rank(
        unordered: [_entry('a', seconds: 100), _entry('b', seconds: 300)],
        previousRanks: const {},
      );
      // Entries built by the provider carry streak/level through ranking.
      final withMeta = Leaderboard.rank(
        unordered: [
          const LeaderboardEntry(
            memberId: 'a',
            displayName: 'A',
            avatarId: 'avatar1',
            blobVariant: 0,
            isSelf: false,
            weekSeconds: 100,
            hasData: true,
            rank: 0,
            streakDays: 4,
            level: 3,
          ),
        ],
        previousRanks: const {},
      );
      expect(withMeta.single.streakDays, 4);
      expect(withMeta.single.level, 3);
      expect(withMeta.single.rank, 1);
      expect(ranked.first.rank, 1);
    });

    test('level math matches the Progress screen formula', () {
      // Tier thresholds: 100 XP = level 2, 500 XP = level 6 (Apprentice).
      expect(computeStudyLevel(99).level, 1);
      expect(computeStudyLevel(100).level, 2);
      expect(computeStudyLevel(500).level, 6);
    });
  });
}
