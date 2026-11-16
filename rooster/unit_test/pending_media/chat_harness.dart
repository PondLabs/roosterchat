import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/command/command_component.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/emoticon/emoji_pack.dart';
import 'package:rooster/client/components/emoticon/emoticon_component.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/threads/thread_component.dart';
import 'package:rooster/client/matrix/matrix_attachment.dart';
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/client/permissions.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:rooster/ui/organisms/chat/chat.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import '../media_prepare/fakes.dart';

/// The real [Chat] (composer, Send, the pending files' slots) on rooms
/// that record what they are asked to send, with the picture preparation
/// replaced by [FakeEngine]: no Matrix SDK, so it runs inside the widget
/// test's fake time.

/// One `sendMessage` a room or a thread received.
class SentMessage {
  SentMessage(this.room,
      {this.message,
      this.inReplyTo,
      this.replaceEvent,
      this.threadRootEventId,
      this.files = const []});

  final FakeRoom room;
  final String? message;
  final TimelineEvent? inReplyTo;
  final TimelineEvent? replaceEvent;
  final String? threadRootEventId;
  final List<MatrixProcessedAttachment> files;

  @override
  String toString() => "SentMessage(${room.identifier}, $message, "
      "reply: ${inReplyTo?.eventId}, edit: ${replaceEvent?.eventId}, "
      "thread: $threadRootEventId, files: ${files.length})";
}

/// Everything every fake room and thread was asked to send, in order.
final List<SentMessage> sent = [];

class _Permissions implements Permissions {
  @override
  bool get canSendMessage => true;
  @override
  bool get canUserEditMessages => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Member implements Member {
  _Member(this.identifier);
  @override
  final String identifier;
  @override
  String get displayName => identifier;
  @override
  Color get defaultColor => Colors.teal;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Emoticons implements RoomEmoticonComponent {
  @override
  List<EmoticonPack> get availableEmoji => [];
  @override
  List<EmoticonPack> get availableStickers => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs a message starting with `/` as a command.
class FakeCommands implements CommandComponent {
  final List<(String, Room, TimelineEvent?, EventInteractionType?)> ran = [];

  @override
  List<String> getCommands() => ['shrug'];
  @override
  bool isExecutable(String string) => string.startsWith('/');
  @override
  bool isPossiblyCommand(String string) => string.startsWith('/');
  @override
  Future<void> executeCommand(String string, Room room,
      {TimelineEvent? interactingEvent, EventInteractionType? type}) async {
    ran.add((string, room, interactingEvent, type));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeThreads implements ThreadsComponent {
  @override
  Future<TimelineEvent?> sendMessage(
      {required String threadRootEventId,
      required Room room,
      String? message,
      TimelineEvent? inReplyTo,
      TimelineEvent? replaceEvent,
      List<ProcessedAttachment>? processedAttachments}) async {
    sent.add(SentMessage(room as FakeRoom,
        message: message,
        inReplyTo: inReplyTo,
        replaceEvent: replaceEvent,
        threadRootEventId: threadRootEventId,
        files: [...?processedAttachments?.cast<MatrixProcessedAttachment>()]));
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeClient implements Client {
  FakeClient(this.identifier);

  @override
  final String identifier;
  final Map<Type, Component> components = {};
  final Map<String, Room> roomsById = {};

  @override
  T? getComponent<T extends Component>() => components[T] as T?;
  @override
  int? get maxFileSize => null;
  @override
  Room? getRoom(String identifier) => roomsById[identifier];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRoom implements Room {
  FakeRoom(this.client, this.identifier, {required this.preparer}) {
    client.roomsById[identifier] = this;
  }

  @override
  final FakeClient client;
  @override
  final String identifier;
  final ImagePreparer preparer;

  @override
  String get localId => "${client.identifier}:$identifier";
  @override
  String get displayName => identifier;
  @override
  bool get isE2EE => false;
  @override
  bool get shouldPreviewMedia => true;
  @override
  Permissions get permissions => _Permissions();
  @override
  Timeline? get timeline => null;
  @override
  String? get lastRead => null;
  @override
  T? getComponent<T extends RoomComponent>() =>
      T == RoomEmoticonComponent ? _Emoticons() as T : null;
  @override
  Future<Timeline> getTimeline({String? contextEventId}) =>
      Completer<Timeline>().future;
  @override
  Member getMemberOrFallback(String id) => _Member(id);
  @override
  Color getColorOfUser(String userId) => Colors.teal;

  /// What the Matrix room does: the picture's preparation reused.
  @override
  Future<List<ProcessedAttachment>> processAttachments(
      List<PendingFileAttachment> attachments) async {
    final files = await Future.wait(attachments
        .map((a) => matrixFilesForAttachment(a, preparer: preparer)));
    return files.nonNulls.toList();
  }

  @override
  Future<TimelineEvent?> sendMessage(
      {String? message,
      TimelineEvent? inReplyTo,
      TimelineEvent? replaceEvent,
      List<ProcessedAttachment>? processedAttachments}) async {
    sent.add(SentMessage(this,
        message: message,
        inReplyTo: inReplyTo,
        replaceEvent: replaceEvent,
        files: [...?processedAttachments?.cast<MatrixProcessedAttachment>()]));
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A message of someone's in the room, to reply to or edit.
class FakeMessage implements TimelineEventMessage {
  FakeMessage(this.eventId, {this.senderId = '@bob:example.org'});
  @override
  final String eventId;
  @override
  final String senderId;
  @override
  String get plainTextBody => 'an earlier message';
  @override
  String getPlaintextBody(Timeline timeline) => plainTextBody;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A JPEG of [width] by [height] that the engine draws (the composer shows
/// it), all black.
Uint8List blackJpeg(int width, int height) =>
    img.encodeJpg(img.Image(width: width, height: height), quality: 80);

/// A [FakeEngine] whose decodes each take [delay] of the test's time.
FakeEngine slowEngine(Duration delay) =>
    FakeEngine(width: 4032, height: 3024, gate: () => Future.delayed(delay));

Widget chatApp(Room room, {String? threadId}) => MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(body: Chat(room, threadId: threadId)),
    );

ChatState chatState(WidgetTester tester) =>
    tester.state<ChatState>(find.byType(Chat));

/// The composer's text.
String composerText(WidgetTester tester) => tester
    .widget<EditableText>(find.byType(EditableText).first)
    .controller
    .text;

/// Types [text] in the composer and presses its Send button. Pumps the
/// composer's 20 ms debounce: the frame drawn at its end is the first one
/// after Send.
Future<void> typeAndSend(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText).first, text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.send));
  await tester.pump(const Duration(milliseconds: 20));
}

/// Takes the chat down and lets its timers (typing, keyboard) run out.
Future<void> closeChat(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}
