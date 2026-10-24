import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Summarized weekly performance returned by the secure backend RPCs.
class WeeklyCardSummary {
  final DateTime weekStart;
  final int completedSessions;
  final int totalMinutes;
  final int goalMinutes;
  final int percent;
  final int streak;

  const WeeklyCardSummary({
    required this.weekStart,
    required this.completedSessions,
    required this.totalMinutes,
    required this.goalMinutes,
    required this.percent,
    required this.streak,
  });

  factory WeeklyCardSummary.empty(DateTime weekStart) {
    return WeeklyCardSummary(
      weekStart: weekStart,
      completedSessions: 0,
      totalMinutes: 0,
      goalMinutes: 600,
      percent: 0,
      streak: 0,
    );
  }

  factory WeeklyCardSummary.fromJson(Map<String, dynamic> json) {
    final wsStr = json['week_start'] as String?;
    final ws = wsStr != null ? DateTime.parse(wsStr) : DateTime.now();
    return WeeklyCardSummary(
      weekStart: ws,
      completedSessions: (json['completed_sessions'] as num?)?.toInt() ?? 0,
      totalMinutes: (json['total_minutes'] as num?)?.toInt() ?? 0,
      goalMinutes: (json['goal_minutes'] as num?)?.toInt() ?? 600,
      percent: (json['percent'] as num?)?.toInt() ?? 0,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
    );
  }

  String get formattedStudyTime {
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  String get formattedGoal {
    final hours = goalMinutes ~/ 60;
    final mins = goalMinutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }
}

/// Summarized today performance returned by get_community_home.
class TodayCardSummary {
  final DateTime date;
  final int completedSessions;
  final int totalMinutes;

  const TodayCardSummary({
    required this.date,
    required this.completedSessions,
    required this.totalMinutes,
  });

  factory TodayCardSummary.empty(DateTime date) {
    return TodayCardSummary(
      date: date,
      completedSessions: 0,
      totalMinutes: 0,
    );
  }

  factory TodayCardSummary.fromJson(Map<String, dynamic> json) {
    final dStr = json['date'] as String?;
    final d = dStr != null ? DateTime.parse(dStr) : DateTime.now();
    return TodayCardSummary(
      date: d,
      completedSessions: (json['completed_sessions'] as num?)?.toInt() ?? 0,
      totalMinutes: (json['total_minutes'] as num?)?.toInt() ?? 0,
    );
  }

  String get formattedStudyTime {
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }
}

/// Full community home model returned by get_community_home.
class CommunityHomeData {
  final CommunityMember me;
  final WeeklyCardSummary meWeekly;
  final TodayCardSummary meToday;
  final List<CommunityMember> friends;
  final List<CommunityMember> allRankedMembers;

  const CommunityHomeData({
    required this.me,
    required this.meWeekly,
    required this.meToday,
    required this.friends,
    required this.allRankedMembers,
  });

  CommunityMember? get topFriend => friends.isNotEmpty
      ? (List<CommunityMember>.from(friends)
        ..sort((a, b) => b.weeklyMinutes.compareTo(a.weeklyMinutes))).first
      : null;

  bool get hasFriends => friends.isNotEmpty;
}

/// Representation of a real student member in the Community circle.
class CommunityMember {
  final String id;
  final String name;
  final String? avatarUrl;
  final Color avatarColor;
  final int weeklyMinutes;
  final int completedSessions;
  final int percent;
  final int streakDays;
  final bool isCurrentUser;

  const CommunityMember({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.avatarColor,
    required this.weeklyMinutes,
    this.completedSessions = 0,
    this.percent = 0,
    this.streakDays = 0,
    this.isCurrentUser = false,
  });

  static Color _colorForId(String id) {
    const palette = [
      AppColors.cta,
      AppColors.blue,
      AppColors.primary,
      AppColors.pink,
      AppColors.orange,
      AppColors.green,
    ];
    final hash = id.codeUnits.fold(0, (acc, c) => acc + c);
    return palette[hash % palette.length];
  }

  factory CommunityMember.fromFriendJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final name = (json['name'] as String?)?.trim() ?? 'Study Friend';
    final cardJson = json['weekly_card'] as Map<String, dynamic>?;
    final weekly = cardJson != null ? WeeklyCardSummary.fromJson(cardJson) : null;

    return CommunityMember(
      id: id,
      name: name.isEmpty ? 'Study Friend' : name,
      avatarUrl: json['avatar'] as String?,
      avatarColor: _colorForId(id),
      weeklyMinutes: weekly?.totalMinutes ?? 0,
      completedSessions: weekly?.completedSessions ?? 0,
      percent: weekly?.percent ?? 0,
      streakDays: weekly?.streak ?? 0,
      isCurrentUser: false,
    );
  }

  factory CommunityMember.fromMeJson(
    Map<String, dynamic> meJson,
    WeeklyCardSummary weekly,
  ) {
    final id = meJson['id'] as String? ?? 'me';
    final name = (meJson['name'] as String?)?.trim() ?? 'You';

    return CommunityMember(
      id: id,
      name: name.isEmpty ? 'You' : name,
      avatarUrl: meJson['avatar'] as String?,
      avatarColor: AppColors.cta,
      weeklyMinutes: weekly.totalMinutes,
      completedSessions: weekly.completedSessions,
      percent: weekly.percent,
      streakDays: weekly.streak,
      isCurrentUser: true,
    );
  }

  String get formattedStudyTime {
    final hours = weeklyMinutes ~/ 60;
    final mins = weeklyMinutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// Day-by-day record in a 7-day week breakdown.
class DayDetailSummary {
  final DateTime date;
  final int minutes;
  final int sessionsCompleted;

  const DayDetailSummary({
    required this.date,
    required this.minutes,
    required this.sessionsCompleted,
  });

  factory DayDetailSummary.fromJson(Map<String, dynamic> json) {
    final dStr = json['date'] as String?;
    final d = dStr != null ? DateTime.parse(dStr) : DateTime.now();
    return DayDetailSummary(
      date: d,
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      sessionsCompleted: (json['sessions_completed'] as num?)?.toInt() ?? 0,
    );
  }

  String get shortDayName {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekday = date.weekday; // 1 = Mon ... 7 = Sun
    return names[(weekday - 1) % 7];
  }

  String get formattedStudyTime {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }
}

/// 7-day week detail summary returned by get_week_detail RPC.
class WeekDetailSummary {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final bool isMe;
  final WeeklyCardSummary weeklyCard;
  final List<DayDetailSummary> days;

  const WeekDetailSummary({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    required this.isMe,
    required this.weeklyCard,
    required this.days,
  });

  factory WeekDetailSummary.fromJson(Map<String, dynamic> json) {
    final u = json['user'] as Map<String, dynamic>? ?? {};
    final w = json['weekly_card'] as Map<String, dynamic>? ?? {};
    final dList = json['days'] as List<dynamic>? ?? [];

    return WeekDetailSummary(
      userId: u['id'] as String? ?? '',
      userName: (u['name'] as String?)?.trim() ?? 'Study Friend',
      avatarUrl: u['avatar'] as String?,
      isMe: u['is_me'] as bool? ?? false,
      weeklyCard: WeeklyCardSummary.fromJson(w),
      days: dList
          .map((item) => DayDetailSummary.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
