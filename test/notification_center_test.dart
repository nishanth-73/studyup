import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/notifications/notification_service.dart';
import 'package:studyup/features/notifications/data/app_notification.dart';

void main() {
  group('CenterItem storage rules', () {
    test('upsert adds once, updates in place, preserves read', () {
      final items = <CenterItem>[];
      final first = CenterItem(
        id: 'task:a',
        kind: CenterItemKind.taskReminder,
        title: 'A',
        body: 'Today · 9:00 AM',
        at: DateTime(2026, 10, 13, 8),
        dayKey: '2026-10-13',
      );
      expect(upsertCenterItem(items, first), isTrue);
      expect(items.length, 1);

      final edited = first.copyWith(title: 'A (edited)', read: false);
      expect(upsertCenterItem(items, edited), isFalse);
      expect(items.length, 1);
      expect(items.single.title, 'A (edited)');
      // Stored read flag wins over the incoming one.
      expect(items.single.read, isFalse);
    });

    test('prune drops past task rows but keeps goal history', () {
      final items = [
        CenterItem(
          id: 'task:old',
          kind: CenterItemKind.taskReminder,
          title: 'Old',
          body: '',
          at: DateTime(2026, 10, 10),
          dayKey: '2026-10-10',
        ),
        CenterItem(
          id: 'task:today',
          kind: CenterItemKind.taskReminder,
          title: 'Today',
          body: '',
          at: DateTime(2026, 10, 13),
          dayKey: '2026-10-13',
        ),
        CenterItem(
          id: 'goal:2026-10-10',
          kind: CenterItemKind.goalReached,
          title: 'Goal',
          body: '',
          at: DateTime(2026, 10, 10),
          dayKey: '2026-10-10',
        ),
      ];
      prunePastTaskItems(items, '2026-10-13');
      expect(items.map((i) => i.id), ['task:today', 'goal:2026-10-10']);
    });

    test('unknown kinds and missing read flag degrade safely', () {
      final item = CenterItem.fromJson({
        'id': 'x',
        'kind': 'nope',
        'title': 'T',
        'body': 'B',
        'at': '2026-10-13T10:00:00.000',
        'dayKey': '2026-10-13',
      });
      expect(item.kind, CenterItemKind.taskReminder);
      expect(item.read, isTrue);
    });

    test('time labels use the 12-hour clock', () {
      expect(centerTimeLabel(0), '12:00 AM');
      expect(centerTimeLabel(540), '9:00 AM');
      expect(centerTimeLabel(810), '1:30 PM');
    });
  });

  group('Center persistence + unread policy', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      NotificationService.instance.unreadCount.value = 0;
    });

    test('task record lights the dot once, edits never duplicate', () async {
      final service = NotificationService.instance;
      final now = DateTime(2026, 10, 13, 8);
      await service.recordCenterTask(
        taskId: 'a',
        title: 'Algebra',
        date: DateTime(2026, 10, 13),
        startMinutes: 540,
        now: now,
      );
      expect(service.unreadCount.value, 1);
      var items = await service.loadCenterItems();
      expect(items.length, 1);
      expect(items.single.body, contains('9:00 AM'));

      // Edit: same stable id, content updates, no duplicate, dot unchanged.
      await service.recordCenterTask(
        taskId: 'a',
        title: 'Algebra II',
        date: DateTime(2026, 10, 13),
        startMinutes: 600,
        now: now,
      );
      items = await service.loadCenterItems();
      expect(items.length, 1);
      expect(items.single.title, 'Algebra II');
      expect(service.unreadCount.value, 1);
    });

    test('removing a task row clears its unread contribution', () async {
      final service = NotificationService.instance;
      final now = DateTime(2026, 10, 13, 8);
      await service.recordCenterTask(
        taskId: 'a',
        title: 'A',
        date: DateTime(2026, 10, 13),
        startMinutes: 540,
        now: now,
      );
      await service.recordCenterTask(
        taskId: 'b',
        title: 'B',
        date: DateTime(2026, 10, 13),
        startMinutes: 600,
        now: now,
      );
      expect(service.unreadCount.value, 2);
      await service.removeCenterTaskItem('a');
      expect(service.unreadCount.value, 1);
      expect((await service.loadCenterItems()).map((i) => i.id), ['task:b']);
    });

    test('goal rows record once per day and survive reloads', () async {
      final service = NotificationService.instance;
      final now = DateTime(2026, 10, 13, 20);
      await service.recordGoalReached(
        minutesToday: 480,
        goalMinutes: 480,
        now: now,
      );
      await service.recordGoalReached(
        minutesToday: 500,
        goalMinutes: 480,
        now: now.add(const Duration(minutes: 20)),
      );
      final items = await service.loadCenterItems();
      expect(
        items.where((i) => i.kind == CenterItemKind.goalReached).length,
        1,
      );
      expect(service.unreadCount.value, 1);
    });

    test('opening policy: mark-all-read persists across restarts', () async {
      final service = NotificationService.instance;
      await service.recordGoalReached(
        minutesToday: 480,
        goalMinutes: 480,
        now: DateTime(2026, 10, 13, 20),
      );
      await service.markCenterAllRead();
      expect(service.unreadCount.value, 0);
      final items = await service.loadCenterItems();
      expect(items.every((i) => i.read), isTrue);
    });

    test('day reset prunes yesterday without touching goal history', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'studyup.notif.centerItems.v1',
        '''
[{"id":"task:old","kind":"taskReminder","title":"Old","body":"","at":"2026-10-12T10:00:00.000","dayKey":"2026-10-12","read":false},
 {"id":"goal:2026-10-12","kind":"goalReached","title":"Goal","body":"","at":"2026-10-12T20:00:00.000","dayKey":"2026-10-12","read":true}]''',
      );
      final service = NotificationService.instance;
      final items = await service.loadCenterItems();
      expect(items.map((i) => i.id), ['goal:2026-10-12']);
    });
  });
}
