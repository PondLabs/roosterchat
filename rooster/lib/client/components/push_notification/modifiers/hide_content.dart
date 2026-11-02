import 'package:rooster/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:intl/intl.dart';

class NotificationModifierHideContent implements NotificationModifier {
  // Also the text of a message notification whose message has no text of
  // its own (one still encrypted, say).
  static String get notificationModifiersPrivacyEnhanced => Intl.message(
      "Sent a message",
      name: "notificationModifiersPrivacyEnhanced",
      desc:
          "Placeholder text to put in a notification when the user has privacy enhanced notifications enabled.");

  static String get messageNotificationHiddenContent =>
      Intl.message("A Notification was received",
          name: "messageNotificationHiddenContent",
          desc: "Text of a notification other than a message when "
              "notification contents are hidden for privacy");

  @override
  Future<NotificationContent?> process(NotificationContent content,
      {Function(String reason)? onNotificationRejected}) async {
    content.content = messageNotificationHiddenContent;

    if (content is MessageNotificationContent) {
      content.content = notificationModifiersPrivacyEnhanced;
    }

    return content;
  }
}
