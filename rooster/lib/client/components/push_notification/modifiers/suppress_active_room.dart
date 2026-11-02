import 'package:rooster/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/event_bus.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:window_manager/window_manager.dart';

class NotificationModifierSuppressActiveRoom implements NotificationModifier {
  static String get messageNotificationSuppressedActiveRoom => Intl.message(
      "The notification was intended for the same room that is currently "
      "open, and the app was detected as being in focus. If this doesn't seem "
      "right, you may want to disable the 'Hide notifications for current "
      "room' setting to bypass this check",
      name: "messageNotificationSuppressedActiveRoom",
      desc: "In the notification debugger (Developer settings): why a test "
          "notification was not shown. Names the notification setting 'Hide "
          "notifications for current room'; use that setting's translated "
          "name");

  String? roomId = "";

  NotificationModifierSuppressActiveRoom() {
    EventBus.onSelectedRoomChanged.stream.listen((event) {
      roomId = event?.identifier;
    });
  }

  @override
  Future<NotificationContent?> process(NotificationContent content,
      {Function(String reason)? onNotificationRejected}) async {
    if (preferences.suppressNotificationWhenRoomFocused.value == false) {
      return content;
    }

    if (content is MessageNotificationContent) {
      if (PlatformUtils.isLinux || PlatformUtils.isWindows) {
        if (!await windowManager.isFocused()) {
          return content;
        }
      } else {
        if (WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed) {
          return content;
        }
      }

      if (content.roomId == roomId) {
        onNotificationRejected?.call(messageNotificationSuppressedActiveRoom);
        return null;
      }
    }

    return content;
  }
}
