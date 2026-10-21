import 'package:flutter/foundation.dart';

/// In-app notification-center item kinds. [taskReminder] and [goalReached]
/// light the unread indicator; the live entry is a single per-day logical
/// item whose value updates never flip unread.
enum CenterItemKind { taskReminder, liveProgress, goalReached }

/// One in-app notification-center row, persisted as JSON in
/// SharedPreferences (the app's existing settings storage).
///
/// Identity is stable per logical event so updates never duplicate rows:
/// - task reminders: `'task:<taskId>'` (same id across edits/reschedules),
/// - live progress: `'live:<dayKey>'` (one row per local day),
/// - goal reached: `'goal:<dayKey>'` (at most one per local day).
@immutable
class CenterItem {
  final String id;
  final CenterItemKind kind;
  final String title;
  final String body;
  final DateTime at;
  final String dayKey;
  final bool read;

  /// Task-only scheduling context, kept so the center can show when the
  /// task fires and prune stale upcoming rows at day boundaries.
  final DateTime? taskDate;
  final int? taskStartMinutes;

  const CenterItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.at,
    required this.dayKey,
    this.read = false,
    this.taskDate,
    this.taskStartMinutes,
  });

  CenterItem copyWith({
    String? title,
    String? body,
    DateTime? at,
    bool? read,
    DateTime? taskDate,
    int? taskStartMinutes,
  }) => CenterItem(
    id: id,
    kind: kind,
    title: title ?? this.title,
    body: body ?? this.body,
    at: at ?? this.at,
    dayKey: dayKey,
    read: read ?? this.read,
    taskDate: taskDate ?? this.taskDate,
    taskStartMinutes: taskStartMinutes ?? this.taskStartMinutes,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'body': body,
    'at': at.toIso8601String(),
    'dayKey': dayKey,
    'read': read,
    'taskDate': taskDate?.toIso8601String(),
    'taskStartMinutes': taskStartMinutes,
  };

  factory CenterItem.fromJson(Map<String, Object?> json) {
    CenterItemKind kind;
    try {
      kind = CenterItemKind.values.byName(json['kind']! as String);
    } catch (_) {
      kind = CenterItemKind.taskReminder;
    }
    return CenterItem(
      id: json['id']! as String,
      kind: kind,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime(2000),
      dayKey: json['dayKey'] as String? ?? '',
      read: json['read'] as bool? ?? true,
      taskDate: json['taskDate'] == null
          ? null
          : DateTime.tryParse(json['taskDate']! as String),
      taskStartMinutes: (json['taskStartMinutes'] as num?)?.toInt(),
    );
  }
}

/// Upserts [item] by stable id (update in place, never a duplicate row).
/// Returns true when the list gained a genuinely new row.
bool upsertCenterItem(List<CenterItem> items, CenterItem item) {
  for (var i = 0; i < items.length; i++) {
    if (items[i].id == item.id) {
      // Preserve the stored read flag: reschedules/edits must not
      // re-light the unread dot for an already-read row.
      items[i] = item.copyWith(read: items[i].read);
      return false;
    }
  }
  items.add(item);
  return true;
}

/// Drops task-reminder rows whose local day already passed. Goal history
/// is kept; the live row is derived, never stored.
void prunePastTaskItems(List<CenterItem> items, String todayKey) {
  items.removeWhere(
    (item) =>
        item.kind == CenterItemKind.taskReminder &&
        item.dayKey.compareTo(todayKey) < 0,
  );
}

/// 'h:MM AM' label for a task's start minutes.
String centerTimeLabel(int startMinutes) {
  final h24 = (startMinutes ~/ 60) % 24;
  final m = (startMinutes % 60).toString().padLeft(2, '0');
  final period = h24 >= 12 ? 'PM' : 'AM';
  var h = h24 % 12;
  if (h == 0) h = 12;
  return '$h:$m $period';
}
