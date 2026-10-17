import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// First-launch anchor: attendance tracking begins ONLY from this date.
/// Dates before it are permanently disabled/crossed out.
@immutable
class AppMetadata {
  final DateTime firstLaunchDate;

  const AppMetadata({required this.firstLaunchDate});

  DateTime get firstLaunchDay => DateTime(
    firstLaunchDate.year,
    firstLaunchDate.month,
    firstLaunchDate.day,
  );

  Map<String, Object?> toJson() => {
    'firstLaunchDate': firstLaunchDate.toIso8601String(),
  };

  factory AppMetadata.fromJson(Map<String, Object?> json) => AppMetadata(
    firstLaunchDate: DateTime.parse(json['firstLaunchDate']! as String),
  );

  factory AppMetadata.now() => AppMetadata(firstLaunchDate: DateTime.now());
}

class AppMetadataController extends StateNotifier<AsyncValue<AppMetadata>> {
  AppMetadataController() : super(const AsyncValue.loading()) {
    unawaited(_load());
  }

  static const _storageKey = 'studyup.appMetadata.v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) {
        final fresh = AppMetadata.now();
        final saved = await prefs.setString(_storageKey, _encode(fresh));
        if (!saved) throw StateError('Could not persist first-launch date.');
        state = AsyncValue.data(fresh);
      } else {
        state = AsyncValue.data(
          AppMetadata.fromJson(Map<String, Object?>.from(_decode(raw) as Map)),
        );
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  String _encode(AppMetadata m) =>
      '{"firstLaunchDate":"${m.firstLaunchDate.toIso8601String()}"}';

  Map<String, Object?> _decode(String raw) {
    final marker = '"firstLaunchDate":"';
    final start = raw.indexOf(marker) + marker.length;
    final end = raw.indexOf('"', start);
    return {'firstLaunchDate': raw.substring(start, end)};
  }
}

final appMetadataProvider =
    StateNotifierProvider<AppMetadataController, AsyncValue<AppMetadata>>(
      (ref) => AppMetadataController(),
    );

/// Attendance status for a calendar day.
enum AttendanceStatus { disabled, present, absent, pending }

/// Pure rule used by calendar + tests.
AttendanceStatus attendanceStatusFor({
  required DateTime day,
  required DateTime? firstLaunchDay,
  required DateTime today,
  required bool hasSession,
}) {
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  if (firstLaunchDay != null) {
    final f = DateTime(
      firstLaunchDay.year,
      firstLaunchDay.month,
      firstLaunchDay.day,
    );
    if (d.isBefore(f)) return AttendanceStatus.disabled;
  }
  if (d.isAfter(t)) return AttendanceStatus.pending;
  if (hasSession) return AttendanceStatus.present;
  if (d.isAtSameMomentAs(t)) return AttendanceStatus.pending;
  return AttendanceStatus.absent;
}
