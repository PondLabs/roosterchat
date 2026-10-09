// The browser's notifications (the Notification API): what the desktop
// notifiers are on Linux and Windows. The web had no notifier at all, so a
// message in a background tab showed nothing, and nothing in the settings
// said so.
//
// Only while the page is hidden or another window has the focus: a page in
// front of the user shows the message itself. Clicking one brings the
// window back and opens the room.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:rooster/client/components/push_notification/notifier.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:web/web.dart' as web;

Notifier createWebNotifier() => WebNotifier();

class WebNotifier implements Notifier {
  /// Open notifications by room, closed when the room is read here.
  final Map<String, List<web.Notification>> _shown = {};

  /// Whether this browser has the API at all (an http origin, and some
  /// browsers in some modes, do not).
  static bool get supported => web.window.has('Notification');

  @override
  bool get hasPermission =>
      supported && web.Notification.permission == 'granted';

  /// Whether asking is still possible: a refusal is final until the user
  /// changes it in the browser.
  bool get canAsk => supported && web.Notification.permission == 'default';

  @override
  bool get needsToken => false;

  @override
  bool get enabled => true;

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
  Future<bool> requestPermission() async {
    if (!supported) return false;
    try {
      final result = await web.Notification.requestPermission().toDart;
      return result.toDart == 'granted';
    } catch (e, s) {
      Log.onError(e, s, content: "Could not ask for notification permission");
      return false;
    }
  }

  @override
  Future<void> notify(NotificationContent notification) async {
    if (!hasPermission) return;
    if (!web.document.hidden && web.document.hasFocus()) return;

    final message =
        notification is MessageNotificationContent ? notification : null;
    final title = message != null && !message.isDirectMessage
        ? MessageNotificationContent.labelNotificationSenderInRoom(
            message.senderName, message.roomName)
        : notification.title;
    final options = web.NotificationOptions(
      body: notification.content,
      icon: 'icons/Icon-192.png',
      // One per event: a repeat of the same event replaces itself.
      tag: message?.eventId ?? notification.hashCode.toString(),
    );
    final shown = web.Notification(title, options);
    shown.onclick = ((web.Event _) {
      web.window.focus();
      if (message != null) {
        EventBus.doOpenRoom(message.roomId, clientId: message.clientId);
      }
      shown.close();
    }).toJS;
    if (message != null) {
      final forRoom = _shown.putIfAbsent(message.roomId, () => []);
      forRoom.add(shown);
      shown.onclose = ((web.Event _) => forRoom.remove(shown)).toJS;
    }
  }

  @override
  Future<void> clearNotifications(Room room) async {
    final shown = _shown.remove(room.identifier);
    if (shown == null) return;
    for (final notification in List.of(shown)) {
      notification.close();
    }
  }
}
