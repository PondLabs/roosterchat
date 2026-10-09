import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/direct_messages/direct_message_component.dart';
import 'package:rooster/client/components/push_notification/modifiers/hide_content.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:rooster/client/timeline_events/timeline_event_sticker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum NotificationPriority { normal, low }

class NotificationContent {
  String title;
  String content;
  NotificationPriority priority;

  NotificationContent(
      {required this.title,
      required this.content,
      this.priority = NotificationPriority.normal});
}

class ErrorNotificationContent extends NotificationContent {
  ErrorNotificationContent({required super.title, required super.content});

  static String get labelNotificationUnknownData =>
      Intl.message("Unknown Notification Data",
          name: "labelNotificationUnknownData",
          desc: "Title of a notification shown in developer mode on Android "
              "when a push arrives that the app cannot read; the raw data is "
              "its text");

  static String get labelNotificationProcessingError =>
      Intl.message("An error occurred while processing notifications",
          name: "labelNotificationProcessingError",
          desc: "Title of a notification on Android when an incoming "
              "notification could not be handled; the technical error is its "
              "text");
}

class GenericRoomInviteNotificationContent extends NotificationContent {
  GenericRoomInviteNotificationContent(
      {required super.title, required super.content});

  static String get labelNotificationRoomInvite => Intl.message("Room Invite",
      name: "labelNotificationRoomInvite",
      desc: "Title of the notification on Android when someone invites you "
          "to a room");

  static String get messageNotificationInvitationReceived =>
      Intl.message("You received an invitation to chat!",
          name: "messageNotificationInvitationReceived",
          desc: "Text of the notification on Android when someone invites you "
              "to a room");
}

class MessageNotificationContent extends NotificationContent {
  /// The title of a message's notification from a room that is not a direct
  /// message: who sent it, and the room.
  static String labelNotificationSenderInRoom(String sender, String room) =>
      Intl.message("$sender ($room)",
          name: "labelNotificationSenderInRoom",
          args: [sender, room],
          desc: "Title of a message's notification on Linux and in the "
              "browser: the sender's name, then the room's name in "
              "parentheses");

  String get senderName => title;
  String senderId;
  String eventId;
  String roomId;
  String clientId;
  String roomName;
  String? formattedContent;
  String? formatType;
  bool isDirectMessage;
  ImageProvider? roomImage;
  String? roomImageId;
  ImageProvider? senderImage;
  String? senderImageId;
  ImageProvider? attachedImage;
  Room? room;

  MessageNotificationContent({
    required String senderName,
    required this.senderId,
    required this.roomName,
    required super.content,
    required this.eventId,
    required this.roomId,
    required this.clientId,
    required this.isDirectMessage,
    this.formattedContent,
    this.formatType,
    this.roomImage,
    this.roomImageId,
    this.senderImage,
    this.senderImageId,
    this.attachedImage,
    this.room,
  }) : super(title: senderName);

  static Future<MessageNotificationContent?> fromEvent(
      TimelineEvent msg, Room room) async {
    var user = await room.fetchMember(msg.senderId);

    if (msg is TimelineEventMessage) {
      return MessageNotificationContent(
        senderName: user.displayName,
        senderImage: user.avatar,
        senderId: user.identifier,
        roomName: room.displayName,
        roomId: room.identifier,
        roomImage: await room.getShortcutImage(),
        content: msg.body ??
            NotificationModifierHideContent
                .notificationModifiersPrivacyEnhanced,
        clientId: room.client.identifier,
        eventId: msg.eventId,
        attachedImage:
            msg.attachments?.whereType<ImageAttachment>().firstOrNull?.image ??
                msg.attachments
                    ?.whereType<VideoAttachment>()
                    .firstOrNull
                    ?.thumbnail,
        formatType: msg.bodyFormat,
        formattedContent: msg.formattedBody,
        room: room,
        isDirectMessage: room.client
                .getComponent<DirectMessagesComponent>()
                ?.isRoomDirectMessage(room) ??
            false,
      );
    }

    if (msg is TimelineEventSticker) {
      return MessageNotificationContent(
        senderName: user.displayName,
        senderImage: user.avatar,
        senderId: user.identifier,
        roomName: room.displayName,
        roomId: room.identifier,
        roomImage: await room.getShortcutImage(),
        content: msg.stickerName,
        clientId: room.client.identifier,
        eventId: msg.eventId,
        attachedImage: msg.stickerImage,
        formattedContent: "",
        room: room,
        formatType: "chat.commet.custom.matrix_plain",
        isDirectMessage: room.client
                .getComponent<DirectMessagesComponent>()
                ?.isRoomDirectMessage(room) ??
            false,
      );
    }

    return null;
  }
}

class CallNotificationContent extends NotificationContent {
  String roomId;
  String senderId;
  String senderName;
  String roomName;
  String clientId;
  String callId;

  bool isDirectMessage;

  ImageProvider? roomImage;
  String? roomImageId;

  ImageProvider? senderImage;
  String? senderImageId;
  Room? room;

  CallNotificationContent({
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.roomName,
    required this.clientId,
    required this.callId,
    required this.isDirectMessage,
    this.senderImage,
    this.senderImageId,
    required super.title,
    required super.content,
    this.roomImage,
    this.roomImageId,
    this.room,
  });
}
