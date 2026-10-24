import 'dart:convert';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'community_models.dart';

class CommunityRepository {
  final SupabaseClient _client;

  CommunityRepository(this._client);

  String? get currentUserId => _client.auth.currentUser?.id;

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Fetches real community home summary from Supabase get_community_home RPC.
  Future<CommunityHomeData> getCommunityHome(DateTime monday) async {
    final mondayStr = _formatDate(monday);
    final response = await _client.rpc(
      'get_community_home',
      params: {'p_week_start': mondayStr},
    );

    final data = response is Map<String, dynamic>
        ? response
        : (jsonDecode(response.toString()) as Map<String, dynamic>);

    final meMap = data['me'] as Map<String, dynamic>? ?? {};
    final meWeekly = WeeklyCardSummary.fromJson(
      meMap['weekly_card'] as Map<String, dynamic>? ?? {},
    );
    final meToday = TodayCardSummary.fromJson(
      meMap['today_card'] as Map<String, dynamic>? ?? {},
    );
    final meMember = CommunityMember.fromMeJson(meMap, meWeekly);

    final friendsRaw = data['friends'] as List<dynamic>? ?? [];
    final friends = friendsRaw
        .map((f) => CommunityMember.fromFriendJson(f as Map<String, dynamic>))
        .toList();

    // Construct unified ranked members list: [me, ...friends]
    final ranked = [meMember, ...friends];
    ranked.sort((a, b) {
      final cmp = b.weeklyMinutes.compareTo(a.weeklyMinutes);
      if (cmp != 0) return cmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return CommunityHomeData(
      me: meMember,
      meWeekly: meWeekly,
      meToday: meToday,
      friends: friends,
      allRankedMembers: ranked,
    );
  }

  /// Fetches real 7-day breakdown for a user and week from Supabase get_week_detail RPC.
  Future<WeekDetailSummary> getWeekDetail(String userId, DateTime monday) async {
    final mondayStr = _formatDate(monday);
    final response = await _client.rpc(
      'get_week_detail',
      params: {'p_user_id': userId, 'p_week_start': mondayStr},
    );

    final data = response is Map<String, dynamic>
        ? response
        : (jsonDecode(response.toString()) as Map<String, dynamic>);

    return WeekDetailSummary.fromJson(data);
  }

  /// Generates a cryptographically secure 24-character token, inserts into invites table,
  /// and returns the complete public invite link.
  Future<String> createInviteLink() async {
    final userId = currentUserId;
    if (userId == null) throw StateError('Must be signed in to create an invitation');

    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-';
    final random = Random.secure();
    final token = List.generate(24, (_) => chars[random.nextInt(chars.length)]).join();

    await _client.from('invites').insert({
      'token': token,
      'inviter_id': userId,
    });

    return 'https://studyup-4x7z.vercel.app/invite/$token';
  }

  /// Accepts an invitation token via accept_invite RPC.
  Future<String> acceptInvite(String token) async {
    final res = await _client.rpc(
      'accept_invite',
      params: {'p_token': token.trim()},
    );
    return res?.toString() ?? 'error';
  }

  /// Subscribes to Realtime Postgres Changes on activity_pings.
  RealtimeChannel subscribeToPings(void Function() onPing) {
    final channel = _client.channel('public:activity_pings:${DateTime.now().millisecondsSinceEpoch}');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'activity_pings',
      callback: (payload) {
        onPing();
      },
    ).subscribe();
    return channel;
  }
}
