import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../data/app_notification.dart';

/// In-app notification-center rows. Live progress is NOT stored here: the
/// center screen renders it from the live session state so there is
/// exactly one logical live item whose per-second value updates never
/// touch history or the unread indicator.
class NotificationCenterController extends StateNotifier<List<CenterItem>> {
  NotificationCenterController() : super(const []) {
    refresh();
  }

  Future<void> refresh() async {
    state = List.unmodifiable(
      await NotificationService.instance.loadCenterItems(),
    );
  }

  Future<void> markAllRead() async {
    await NotificationService.instance.markCenterAllRead();
    await refresh();
  }
}

final notificationCenterProvider =
    StateNotifierProvider<NotificationCenterController, List<CenterItem>>(
      (ref) => NotificationCenterController(),
    );
