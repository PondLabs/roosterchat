import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/push_notification/android/android_notifier.dart';
import 'package:rooster/client/components/push_notification/android/firebase_push_notifier.dart';
import 'package:rooster/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:rooster/client/components/push_notification/linux/linux_notifier.dart';
import 'package:rooster/client/components/push_notification/modifiers/linux_notification_formatting.dart';
import 'package:rooster/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:rooster/client/components/push_notification/modifiers/suppress_active_room.dart';
import 'package:rooster/client/components/push_notification/modifiers/suppress_other_device_active.dart';
import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:rooster/client/components/push_notification/notifier.dart';
import 'package:rooster/client/components/push_notification/web/web_notifier_stub.dart'
    if (dart.library.js_interop) 'package:rooster/client/components/push_notification/web/web_notifier.dart';
import 'package:rooster/client/components/push_notification/windows/windows_notifier.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:rooster/utils/window_management.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

class NotificationManager {
  static Notifier? _notifier;

  static Notifier? get notifier => _notifier;

  @visibleForTesting
  static set notifier(Notifier? value) => _notifier = value;

  // ROOSTER: every room wrapper of every signed-in account listens for its
  // room's notifications, so one message can arrive here more than once.
  // ponytail: last 200 event ids, plenty for messages arriving together.
  static final Set<String> _shownMessageIds = <String>{};

  @visibleForTesting
  static void forgetShownMessages() => _shownMessageIds.clear();

  static final List<NotificationModifier> _modifiers =
      List.empty(growable: true);

  static Future<void>? notifierLoading;

  static Player? _player;

  static Player getSoundPlayer() {
    _player ??= Player(configuration: PlayerConfiguration());
    _player!.setVolume(preferences.notificationsVolume.value);

    return _player!;
  }

  static Future<void> init({bool isBackgroundService = false}) async {
    Log.i("Initializing NotificationManager");
    Log.i("Existing notifier: $_notifier");
    _notifier ??= _getNotifier(isBackgroundService: isBackgroundService);

    _modifiers.clear();
    addModifier(NotificationModifierSuppressActiveRoom());
    if (BuildConfig.ANDROID) {
      addModifier(NotificationModifierSuppressOtherActiveDevice());
    }

    if (PlatformUtils.isLinux) {
      addModifier(NotificationModifierLinuxFormatting());
    }

    notifierLoading = _notifier?.init();
  }

  static Notifier? _getNotifier({bool isBackgroundService = false}) {
    if (PlatformUtils.isLinux) {
      return LinuxNotifier();
    }

    if (PlatformUtils.isWindows) {
      return WindowsNotifier();
    }

    if (PlatformUtils.isWeb) {
      return createWebNotifier();
    }

    if (PlatformUtils.isAndroid) {
      // We dont want the background service to actually listen for incoming notifications
      // The main isolate will listen and pass messages to the service
      if (isBackgroundService) {
        return AndroidNotifier();
      } else {
        if (BuildConfig.ENABLE_GOOGLE_SERVICES) {
          return FirebasePushNotifier();
        }

        return UnifiedPushNotifier();
      }
    }

    return null;
  }

  static void addModifier(NotificationModifier modifier) {
    _modifiers.add(modifier);
  }

  static void removeModifier(NotificationModifier modifier) {
    _modifiers.remove(modifier);
  }

  static Future<void> clearNotifications(Room room) async {
    await notifier?.clearNotifications(room);
  }

  static Future<void> notify(NotificationContent notification,
      {bool forceShow = false,
      Function(String reason)? onNotificationRejected}) async {
    if (_notifier == null) {
      Log.e("Failed to show notification, notifier has not been initialzied");
      onNotificationRejected?.call("Notifier has not been initialized");
      return;
    }

    NotificationContent? content = notification;

    if (preferences.enableNotifications.value == false) {
      return;
    }

    // Before any await: the copies arrive together.
    if (notification is MessageNotificationContent && !forceShow) {
      if (!_shownMessageIds.add(notification.eventId)) {
        onNotificationRejected?.call("This message was already shown");
        return;
      }
      if (_shownMessageIds.length > 200) {
        _shownMessageIds.remove(_shownMessageIds.first);
      }
    }

    for (var modifier in _modifiers) {
      Log.d("Processing modifier: $modifier");
      if (forceShow) {
        if (modifier is NotificationModifierSuppressActiveRoom) continue;
        if (modifier is NotificationModifierSuppressOtherActiveDevice) continue;
      }

      content = await modifier.process(content!,
          onNotificationRejected: onNotificationRejected);
      if (content == null) {
        Log.d("Modifier returned null notification, returning");

        onNotificationRejected?.call(
            "Notification modifier '${modifier}' rejected the notification");
        return;
      }
    }

    Log.i("Displaying notification content: $content");
    await _notifier!.notify(content!);
  }

  /// What clicking a notification does: open its room, in its space, and
  /// bring the window up (restored, if it was minimized).
  static Future<void> openRoom(String roomId, {String? clientId}) {
    EventBus.doOpenRoom(roomId, clientId: clientId);
    return WindowManagement.bringToFront();
  }
}
