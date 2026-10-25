import 'dart:async';
import 'dart:io';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:rooster/client/components/push_notification/notification_manager.dart';
import 'package:rooster/client/components/push_notification/notifier.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/shortcuts_manager.dart';
import 'package:desktop_notifications/desktop_notifications.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win_toast/win_toast.dart';
import 'package:path/path.dart' as p;

/// [text] for the toast's XML, in an attribute or an element: names,
/// messages and translations may hold a quote, "<" or an ampersand.
String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

class WindowsNotifier implements Notifier {
  static String get promptNotificationSendReply =>
      Intl.message("Send a reply...",
          name: "promptNotificationSendReply",
          desc: "Placeholder in the reply field of a message notification on "
              "Windows");

  @override
  bool get hasPermission => true;

  @override
  bool get enabled => true;

  @override
  bool get needsToken => false;

  static NotificationsClient client = NotificationsClient();

  @override
  Future<void> init() async {
    final dir = await getTemporaryDirectory();
    var file = p.join(dir.path, "com.pondlabs.rooster", "rooster_app_icon.png");

    ByteData data = await rootBundle
        .load("assets/images/app_icon/app_icon_transparent_cropped.png");

    var imageFile = File(file);
    imageFile.createSync(recursive: true);
    imageFile.writeAsBytes(data.buffer.asInt8List());
    var uri = Uri.file(file, windows: true);

    await WinToast.instance().initialize(
      aumId: 'com.pondlabs.rooster',
      displayName: BuildConfig.app,
      iconPath: uri.toString(),
      clsid: '7685C041-9D17-4112-8FC4-386743A3D53E',
    );

    WinToast.instance().setActivatedCallback(onActivated);
    WinToast.instance().setDismissedCallback(onDismissed);
  }

  static void onActivated(ActivatedEvent event) {
    var text = Uri.decodeQueryComponent(event.argument);
    var args = Uri.splitQueryString(text);

    print("Got action: $args");

    switch (args['action']) {
      case 'reply':
        var clientId = args['client_id'];
        var roomId = args['room_id'];
        var eventId = args['event_id'];
        var message = event.userInput['reply'];

        if (clientId == null) return;
        if (roomId == null) return;
        if (eventId == null) return;
        if (message == null) return;

        var client = clientManager!.getClient(clientId);

        if (client == null) return;

        if (message.trim().isNotEmpty) {
          client.getRoom(roomId)?.sendMessage(message: message.trim());
        }

        break;
      case 'open_room':
        var roomId = args['room_id'];
        if (roomId == null) return;

        // ROOSTER: show() alone left a minimized window minimized.
        NotificationManager.openRoom(roomId, clientId: args['client_id']);
        break;
      case 'accept_call':
      case 'reject_call':
        print("Handling call response");
        final callId = args['call_id'];
        final clientId = args['client_id'];
        final session = clientManager?.callManager.currentSessions
            .where(
                (e) => e.sessionId == callId && e.client.identifier == clientId)
            .firstOrNull;

        if (args['action'] == "reject_call") {
          print("Rejecting call");
          session?.declineCall();
        }

        if (args['action'] == "accept_call") {
          print("Accepting call");
          session?.acceptCall(withMicrophone: true);
        }

        break;
    }
  }

  static void onDismissed(DismissedEvent event) {
    print("Notification dismissed");
    print("event: ${event.toString()} ");
  }

  @override
  Future<bool> requestPermission() async {
    return true;
  }

  @override
  Future<void> notify(NotificationContent notification) async {
    switch (notification) {
      case MessageNotificationContent _:
        return displayMessageNotification(notification);
      case CallNotificationContent _:
        return displayCallNotificationContent(notification);
    }
  }

  Future<void> displayCallNotificationContent(
      CallNotificationContent content) async {
    String? avatarFilePath;

    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    var avatar = await ShortcutsManager.getCachedAvatarImage(
        placeholderColor: room.getColorOfUser(content.senderId),
        placeholderText: content.roomName,
        identifier: content.senderId,
        format: ShortcutIconFormat.png,
        shouldZoomOut: false,
        imageProvider: content.senderImage);

    avatarFilePath = avatar == null ? "" : avatar.toFilePath();

    final xml = callToastXml(content, avatarFilePath);

    WinToast.instance().showCustomToast(xml: xml);
  }

  Future<void> displayMessageNotification(
      MessageNotificationContent content) async {
    String? avatarFilePath;

    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    var avatar = await ShortcutsManager.getCachedAvatarImage(
        placeholderColor: room.getColorOfUser(content.senderId),
        placeholderText: content.senderName,
        identifier: content.senderId,
        format: ShortcutIconFormat.png,
        shouldZoomOut: false,
        imageProvider: content.senderImage);

    avatarFilePath = avatar == null ? "" : avatar.toFilePath();

    final xml = messageToastXml(content, avatarFilePath);

    var player = NotificationManager.getSoundPlayer();
    player.open(Media("asset:///assets/sound/message.ogg"));

    WinToast.instance().showCustomToast(xml: xml);
  }

  /// The toast of an incoming call. Every name and text is escaped: one
  /// holding "&" or "<" made the XML invalid, and Windows dropped the toast
  /// without a word.
  static String callToastXml(
      CallNotificationContent content, String avatarFilePath) {
    final f = Uri.encodeComponent;
    final defaultAction =
        "action=open_room&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}&amp;call_id=${f(content.callId)}";

    final header = content.isDirectMessage
        ? ""
        : '''<header
        id="${f(content.roomId)}"
        title="${_xml(content.roomName)}"
        arguments="$defaultAction"/>''';

    return """
<?xml version="1.0" encoding="UTF-8"?>
<toast launch="$defaultAction">
   $header
   <visual>
      <binding template="ToastGeneric">
         <text>${_xml(content.roomName)}</text>
         <text>${_xml(content.content)}</text>
         <image placement='appLogoOverride' src='${_xml(avatarFilePath)}' hint-crop='circle'/>
      </binding>
   </visual>
   <audio silent='true'/>
   <actions>
      <action content="${_xml(CommonStrings.promptAccept)}" activationType="background" arguments="action=accept_call&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}&amp;call_id=${f(content.callId)}" />
      <action content="${_xml(CommonStrings.promptReject)}" activationType="background" arguments="action=reject_call&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}&amp;call_id=${f(content.callId)}" />
   </actions>
</toast>
  """;
  }

  /// The toast of a message, escaped like [callToastXml]'s: a message with
  /// a link holding "&", or a "<3", never showed.
  static String messageToastXml(
      MessageNotificationContent content, String avatarFilePath) {
    final f = Uri.encodeComponent;
    final defaultAction =
        "action=open_room&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}&amp;event_id=${f(content.eventId)}";

    final header = content.isDirectMessage
        ? ""
        : '''<header
        id="${f(content.roomId)}"
        title="${_xml(content.roomName)}"
        arguments="$defaultAction"/>''';

    return """
<?xml version="1.0" encoding="UTF-8"?>
<toast launch="$defaultAction">
   $header
   <visual>
      <binding template="ToastGeneric">
         <text>${_xml(content.senderName)}</text>
         <text>${_xml(content.content)}</text>
         <image placement='appLogoOverride' src='${_xml(avatarFilePath)}' hint-crop='circle'/>
      </binding>
   </visual>
   <audio silent='true'/>
   <actions>
      <input id="reply" type="text" placeHolderContent="${_xml(promptNotificationSendReply)}" />
      <action content="${_xml(CommonStrings.promptReply)}" activationType="background" arguments="action=reply&amp;client_id=${f(content.clientId)}&amp;room_id=${f(content.roomId)}&amp;event_id=${f(content.eventId)}" />
   </actions>
</toast>
  """;
  }

  @override
  Map<String, dynamic>? extraRegistrationData() {
    return null;
  }

  @override
  Future<String?> getToken() async {
    return null;
  }

  @override
  Future<void> clearNotifications(Room room) async {}

  @override
  Future<void> disableBadges() {
    // TODO: implement disableBadges
    throw UnimplementedError();
  }

  @override
  Future<void> enableBadges() {
    // TODO: implement enableBadges
    throw UnimplementedError();
  }
}
