@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/components/command/command_component.dart';
import 'package:rooster/client/components/threads/thread_component.dart';
import 'package:rooster/ui/molecules/message_input.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';
import 'package:rooster/ui/organisms/chat/chat.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import 'chat_harness.dart';

const _slot = ValueKey("pending-file-slot");

void main() {
  late FakeEngine engine;
  late ImagePreparer preparer;
  late FakeClient client;
  late FakeRoom room;
  late FakeRoom otherRoom;
  final appPreparer = ImagePreparer.instance;

  setUp(() {
    sent.clear();
    AttachmentSends.instance.clear();
    // Every picture's preparation takes 2 s.
    engine = slowEngine(const Duration(seconds: 2));
    preparer = fakePreparer(engine);
    ImagePreparer.instance = preparer;
    client = FakeClient('a');
    room = FakeRoom(client, '!room', preparer: preparer);
    otherRoom = FakeRoom(client, '!other', preparer: preparer);
  });

  final appClock = AttachmentSend.clock;

  /// The pending files' clock on the test's fake time.
  void fakeClock(WidgetTester tester) => AttachmentSend.clock = () =>
      Duration(microseconds: tester.binding.clock.now().microsecondsSinceEpoch);

  tearDown(() {
    AttachmentSend.clock = appClock;
    ImagePreparer.instance = appPreparer;
    AttachmentSends.instance.clear();
  });

  /// A photo attached the way the composer attaches one.
  Future<PendingFileAttachment> attachPhoto(WidgetTester tester,
      {int width = 400, int height = 300, String name = 'photo.jpg'}) async {
    final photo =
        PendingFileAttachment(name: name, data: blackJpeg(width, height));
    chatState(tester).addAttachment(photo);
    // The location answer is read from the bytes at once.
    await tester.pump();
    return photo;
  }

  testWidgets(
      'Send with a photo whose preparation takes 2 s: the first frame has '
      'the text sent, a slot of the photo\'s size and an empty, usable '
      'composer', (tester) async {
    fakeClock(tester);
    await tester.pumpWidget(chatApp(room));
    final photo = await attachPhoto(tester);
    expect(photo.hasLocation, isFalse);
    expect(engine.calls, hasLength(1), reason: 'preparing since attached');

    await typeAndSend(tester, 'look at this');

    // The first frame after Send.
    expect(sent.map((m) => (m.room, m.message, m.files.length)),
        [(room, 'look at this', 0)],
        reason: 'the text went without waiting for the photo');
    final slot = find.byKey(_slot);
    expect(slot, findsOneWidget);
    // As the timeline draws a picture: 200 high, its aspect ratio.
    final size = tester.getSize(slot);
    expect(size.height, 200);
    expect(size.width, closeTo(200 * 400 / 300, 0.01));
    expect(find.text(PendingAttachmentStatus.labelPendingFilePreparing),
        findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    expect(composerText(tester), '');
    expect(chatState(tester).attachments, isEmpty);
    expect(chatState(tester).processing, isFalse);

    // The composer works while the photo is still being prepared.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:01'), findsOneWidget);
    await typeAndSend(tester, 'and another thing');
    expect(sent.map((m) => m.message), ['look at this', 'and another thing']);
    expect(sent.every((m) => m.files.isEmpty), isTrue);

    // Prepared: the photo follows, with the size and thumbnail made once.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(sent, hasLength(3));
    final file = sent.last.files.single;
    expect(sent.last.room, room);
    expect(sent.last.message, isNull);
    expect(file.file.info['w'], 400);
    expect(file.file.info['h'], 300);
    expect(file.file.bytes, same(photo.data));
    expect(engine.calls, hasLength(1), reason: 'prepared once');

    await closeChat(tester);
  });

  testWidgets(
      'declining the location question sends nothing, not even the text, '
      'and the composer keeps its text and files', (tester) async {
    final gps = File('unit_test/fixtures/image_metadata/gps_exif.jpg')
        .readAsBytesSync();
    await tester.pumpWidget(chatApp(room));
    final photo = PendingFileAttachment(name: 'beach.jpg', data: gps);
    chatState(tester).addAttachment(photo);
    await tester.pump();
    expect(photo.hasLocation, isTrue);

    await typeAndSend(tester, 'where I was');
    // The dialog opens (the timeline's spinner never lets pumpAndSettle end).
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(chatState(tester).promptChatDontSendFile), findsOneWidget);
    expect(composerText(tester), 'where I was',
        reason: 'kept while the question is open');

    await tester.tap(find.text(chatState(tester).promptChatDontSendFile));
    await tester.pump(const Duration(seconds: 1));

    expect(sent, isEmpty);
    expect(AttachmentSends.instance.all, isEmpty);
    expect(composerText(tester), 'where I was');
    expect(chatState(tester).attachments, [photo]);
    expect(chatState(tester).processing, isFalse);

    // Asked again and accepted: text and file go, the composer clears.
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text(chatState(tester).promptChatSendFile));
    await tester.pump(const Duration(seconds: 3));
    expect(sent.first.message, 'where I was');
    expect(composerText(tester), '');
    expect(chatState(tester).attachments, isEmpty);
    expect(sent.last.files, hasLength(1));

    await closeChat(tester);
  });

  testWidgets('a command typed with a file attached runs as before',
      (tester) async {
    final commands = FakeCommands();
    client.components[CommandComponent] = commands;
    await tester.pumpWidget(chatApp(room));
    final photo = await attachPhoto(tester);

    await typeAndSend(tester, '/shrug');
    await tester.pump(const Duration(seconds: 3));

    expect(commands.ran.map((r) => (r.$1, r.$2)), [('/shrug', room)]);
    // As before: nothing is sent, and the file is dropped with the
    // composer's text.
    expect(sent, isEmpty);
    expect(AttachmentSends.instance.all, isEmpty);
    expect(composerText(tester), '');
    expect(chatState(tester).attachments, isEmpty);
    expect(await photo.imagePreparation(preparer: preparer), isNull,
        reason: 'its preparation was dropped');

    await closeChat(tester);
  });

  group('moving to another room right after Send', () {
    testWidgets('a reply goes to its room, replying to its event',
        (tester) async {
      await tester.pumpWidget(chatApp(room));
      final event = FakeMessage(r'$asked');
      chatState(tester)
          .setInteractingEvent(event, type: EventInteractionType.reply);
      await attachPhoto(tester);
      await typeAndSend(tester, 'here you go');

      await tester.pumpWidget(chatApp(otherRoom));
      expect(chatState(tester).room, otherRoom);
      expect(find.byKey(_slot), findsNothing,
          reason: 'the other room\'s chat does not show it');
      await tester.pump(const Duration(seconds: 3));

      expect(sent.map((m) => (m.room, m.message, m.inReplyTo, m.files.length)),
          [(room, 'here you go', event, 0), (room, null, null, 1)]);
      await closeChat(tester);
    });

    testWidgets('an edit replaces its event in its room', (tester) async {
      await tester.pumpWidget(chatApp(room));
      final event = FakeMessage(r'$mine', senderId: '@a:example.org');
      chatState(tester)
          .setInteractingEvent(event, type: EventInteractionType.edit);
      await typeAndSend(tester, 'fixed typo');
      await tester.pumpWidget(chatApp(otherRoom));
      await tester.pump(const Duration(seconds: 3));

      expect(sent.map((m) => (m.room, m.message, m.replaceEvent)),
          [(room, 'fixed typo', event)]);
      await closeChat(tester);
    });

    testWidgets('a thread message and its file go to their thread',
        (tester) async {
      final threads = FakeThreads();
      client.components[ThreadsComponent] = threads;
      await tester.pumpWidget(chatApp(room, threadId: r'$root'));
      await attachPhoto(tester);
      await typeAndSend(tester, 'in the thread');

      await tester.pumpWidget(chatApp(otherRoom, threadId: r'$elsewhere'));
      await tester.pump(const Duration(seconds: 3));

      expect(
          sent.map(
              (m) => (m.room, m.threadRootEventId, m.message, m.files.length)),
          [(room, r'$root', 'in the thread', 0), (room, r'$root', null, 1)]);
      await closeChat(tester);
    });

    testWidgets('a message sent as the other account goes from it',
        (tester) async {
      final otherAccount = FakeClient('b');
      final roomAsOther =
          FakeRoom(otherAccount, room.identifier, preparer: preparer);
      await tester.pumpWidget(chatApp(room));
      await attachPhoto(tester);

      final result =
          chatState(tester).sendMessage('from b', overrideClient: otherAccount);
      expect(result, MessageInputSendResult.success);
      await tester.pumpWidget(chatApp(otherRoom));
      await tester.pump(const Duration(seconds: 3));

      expect(sent.map((m) => (m.room, m.message, m.files.length)),
          [(roomAsOther, 'from b', 0), (roomAsOther, null, 1)]);
      await closeChat(tester);
    });

    testWidgets('the chat closed: the file is still sent', (tester) async {
      await tester.pumpWidget(chatApp(room));
      await attachPhoto(tester);
      await typeAndSend(tester, 'bye');
      // Closed while the photo is still being prepared (2 s), once the
      // composer's own 1 s keyboard timer has run.
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));

      expect(sent.map((m) => (m.room, m.message, m.files.length)),
          [(room, 'bye', 0), (room, null, 1)]);
      await closeChat(tester);
    });
  });

  testWidgets(
      'a file sent as the other account shows in the chat Send was pressed '
      'in, its failure too', (tester) async {
    final otherAccount = FakeClient('b');
    FakeRoom(otherAccount, room.identifier, preparer: preparer);
    await tester.pumpWidget(chatApp(room));
    await attachPhoto(tester);
    // A file that is gone by the time Send reads it: it fails before the
    // room has a pending event. Its location answer is read off the test's
    // fake time.
    final gone = PendingFileAttachment(
        name: 'gone.zip', path: 'unit_test/fixtures/no_such_file.zip');
    await tester.runAsync(() => gone.locationCheck());
    chatState(tester).addAttachment(gone);
    await tester.pump();

    chatState(tester).sendMessage('from b', overrideClient: otherAccount);
    await tester.pump(const Duration(milliseconds: 20));
    expect(AttachmentSends.instance.all.map((s) => s.roomKey).toSet(),
        {'b:!room'});
    expect(find.byKey(_slot), findsOneWidget);
    expect(find.byType(PendingAttachmentStatus), findsNWidgets(2));

    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text(PendingAttachmentStatus.labelPendingFileFailed),
        findsOneWidget);
    await closeChat(tester);
  });

  testWidgets(
      'the clock of a failed file stops when it failed, Retry restarts it',
      (tester) async {
    var now = Duration.zero;
    AttachmentSend.clock = () => now;
    final send = AttachmentSend(
        roomKey: 'a:!room',
        attachment: PendingFileAttachment(
            name: 'notes.pdf',
            data: blackJpeg(4, 4),
            mimeType: 'application/pdf'));
    now = const Duration(seconds: 5);
    send.failed();
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: PendingAttachmentStatus(send))));
    expect(find.text('0:05'), findsOneWidget);

    // Ten minutes later something rebuilds the message.
    now = const Duration(minutes: 10, seconds: 5);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(1),
                child: PendingAttachmentStatus(send)))));
    expect(find.text('0:05'), findsOneWidget);

    send.retrying();
    now += const Duration(seconds: 3);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:03'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'ten photos attached, five removed before Send: the five left are '
      'sent, each with its own size, and the removed ones never decoded',
      (tester) async {
    await tester.pumpWidget(chatApp(room));
    final photos = [
      for (var i = 0; i < 10; i++)
        await attachPhoto(tester, height: 300 + i, name: 'p$i.jpg')
    ];
    for (final i in [1, 3, 5, 7, 9]) {
      chatState(tester).removeAttachment(photos[i]);
    }
    await tester.pump();
    expect(chatState(tester).attachments, hasLength(5));

    await typeAndSend(tester, 'five pictures');
    await tester.pump(const Duration(seconds: 20));

    final files = [for (final m in sent) ...m.files];
    expect(files.map((f) => (f.file.name, f.file.info['h'])), [
      for (final i in [0, 2, 4, 6, 8]) ('p$i.jpg', 300 + i)
    ]);
    final decoded = engine.calls.map((c) => c.bytes).toList();
    for (final i in [3, 5, 7, 9]) {
      expect(decoded.contains(photos[i].data), isFalse, reason: 'p$i');
    }
    // p1 was decoding when it was removed: thrown away, its codec and
    // image disposed like every other one.
    expect(decoded, hasLength(6));
    for (final codec in engine.codecs) {
      expect(codec.disposed, 1);
    }
    for (final image in engine.images) {
      expect(image.disposed, 1);
    }
    await closeChat(tester);
  });
}
