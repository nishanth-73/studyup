import '../data/community_models.dart';

/// DEMO FIXTURES ONLY — development preview data for the Community
/// screen layout. This file is the single home of all fabricated
/// leaderboard content:
///
/// - Nothing here is read from, or written to, real user sessions,
///   SharedPreferences, or any production database.
/// - A demo friend is display-only: it is never a [CommunityMember],
///   never enters the friendship store, and is never treated as an
///   authenticated user.
/// - Swap [demoEntriesForWeek] for a real leaderboard repository when
///   the social backend lands; all UI consumes plain [LeaderboardEntry].
/// - Streak/level figures below are illustrative (history cannot be
///   reconstructed for fixtures); the screen labels them as demo.
class CommunityDemo {
  const CommunityDemo._();

  static const isDemo = true;

  /// Display-only fixture ids always carry this prefix — the UI tags
  /// them, and they can never collide with real member ids (`u-…`).
  static bool isDemoId(String memberId) => memberId.startsWith('demo-');

  static const _friends = [
    (id: 'demo-maya', name: 'Maya', avatar: 'avatar2', streak: 6, level: 4),
    (id: 'demo-leo', name: 'Leo', avatar: 'avatar4', streak: 3, level: 3),
    (id: 'demo-priya', name: 'Priya', avatar: 'avatar5', streak: 9, level: 5),
    (id: 'demo-sam', name: 'Sam', avatar: 'avatar1', streak: 2, level: 2),
    (id: 'demo-ava', name: 'Ava', avatar: 'avatar6', streak: 5, level: 3),
  ];

  /// Deterministic pseudo-random minutes in [minCap, maxCap] seeded by
  /// friend + week key, so the podium/rows visibly respond when the
  /// selected week changes while staying stable within one week.
  static int demoMinutesFor(String friendId, String weekKey) {
    var hash = 0;
    final seed = '$friendId|$weekKey';
    for (var i = 0; i < seed.length; i++) {
      hash = ((hash * 31) + seed.codeUnitAt(i)) & 0x7fffffff;
    }
    return 120 + (hash % 601); // 2h .. 12h, deterministic per week.
  }

  /// Display-only entries for [weekStart]. Ranks/movement are assigned
  /// later by [Leaderboard.rank] together with the real self entry.
  static List<LeaderboardEntry> demoEntriesForWeek(DateTime weekStart) {
    final key = weekKeyFor(weekStart);
    return [
      for (final f in _friends)
        LeaderboardEntry(
          memberId: f.id,
          displayName: f.name,
          avatarId: f.avatar,
          blobVariant: 0,
          isSelf: false,
          weekSeconds: demoMinutesFor(f.id, key) * 60,
          hasData: true,
          rank: 0,
          streakDays: f.streak,
          level: f.level,
        ),
    ];
  }
}
