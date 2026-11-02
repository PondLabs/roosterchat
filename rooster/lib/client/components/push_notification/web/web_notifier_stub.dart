// Native: the platform notifiers; nothing here is ever asked for. The class
// exists so the settings page, which names it, compiles everywhere.
import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:rooster/client/components/push_notification/notifier.dart';
import 'package:rooster/client/room.dart';

Notifier createWebNotifier() =>
    throw UnsupportedError('The web notifier only exists in the browser');

class WebNotifier implements Notifier {
  static bool get supported => false;

  bool get canAsk => false;

  @override
  bool get hasPermission => false;

  @override
  bool get needsToken => false;

  @override
  bool get enabled => false;

  @override
  Future<String?> getToken() async => null;

  @override
  Map<String, dynamic>? extraRegistrationData() => null;

  @override
  Future<void> init() async {}

  @override
  Future<void> enableBadges() async {}

  @override
  Future<void> disableBadges() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> notify(NotificationContent notification) async {}

  @override
  Future<void> clearNotifications(Room room) async {}
}
