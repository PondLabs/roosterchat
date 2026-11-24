@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/components/threads/thread_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:rooster/diagnostic/speed_log/file_send_trace.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_attachments.dart';
import 'package:rooster/ui/organisms/chat/composer_send.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import '../speed_log/fake_account.dart';
import 'chat_harness.dart' show blackJpeg;
import 'matrix_fakes.dart';

/// A file sent from the composer through the real `MatrixRoom` and Matrix
/// SDK, on the SDK's fake homeserver: its pending event, its stages, its
/// failure.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MediaTransport transport;
  late MatrixClient client;
  late matrix.Client mx;
  late MatrixRoom room;
  final appPreparer = ImagePreparer.instance;

  setUp(() async {
    AttachmentSends.instance.clear();
    ImagePreparer.instance = fakePreparer(FakeEngine(width: 400, height: 300));
    transport = MediaTransport();
    client = await fakeAccount('pending_media_test', transport);
    mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    room = await plainRoom(client);
    transport.seen.clear();
  });

  tearDown(() async {
    ImagePreparer.instance = appPreparer;
    AttachmentSends.instance.clear();
    await client.close();
  });

  test(
      'a pending photo shows its own picture, and its stage is kept by '
      'transaction id from preparing to sent', () async {
    transport.holdUploads = Completer();
    final photo =
        PendingFileAttachment(name: 'photo.jpg', data: blackJpeg(400, 300));
    final echoes = <matrix.Event>[];
    final events = mx.onTimelineEvent.stream.listen(echoes.add);

    composerSend(room, attachments: [photo]).send();
    final send = AttachmentSends.instance.all.single;
    final stages = [send.stage];
    send.addListener(() {
      if (stages.last != send.stage) stages.add(send.stage);
    });
    expect(send.stage, AttachmentSendStage.preparing);
    expect(AttachmentSends.instance.inComposerOf(room.localId, null), [send],
        reason: 'the chat shows it until the room has a pending event');

    await until(() => send.echoed);
    final txid = send.transactionId!;
    final pending = echoes.lastWhere((e) => e.eventId == txid);
    expect(pending.status.isSending, isTrue);
    expect(pending.content['url'], isNull, reason: 'not uploaded yet');

    // The pending event: the picture from the bytes held, at its size, and
    // not the file's name as text.
    final message = room.convertEvent(pending) as MatrixTimelineEventMessage;
    final picture = message.attachments!.single as ImageAttachment;
    expect(picture.image, localPicture(photo.data!),
        reason: 'the same image the chat drew: decoded once');
    expect((picture.width, picture.height), (400.0, 300.0));
    expect(message.buildFormattedContent(), isNull);

    expect(send.stage, AttachmentSendStage.uploading);
    expect(AttachmentSends.instance.byTransaction(room.localId, txid), send);
    expect(AttachmentSends.instance.inComposerOf(room.localId, null), isEmpty,
        reason: 'the pending event took over');

    transport.holdUploads!.complete();
    await until(() => send.isFinished);
    expect(stages, [
      AttachmentSendStage.preparing,
      AttachmentSendStage.uploading,
      AttachmentSendStage.sending,
      AttachmentSendStage.sent,
    ]);
    expect(AttachmentSends.instance.all, isEmpty);
    expect(transport.sentEvents.single['msgtype'], 'm.image');
    expect(transport.uploadSizes.first, photo.data!.length);
    await events.cancel();
  });

  test(
      'an upload the server refuses is a failed message, not an unhandled '
      'error', () async {
    transport.failUploads = true;
    final photo =
        PendingFileAttachment(name: 'photo.jpg', data: blackJpeg(400, 300));
    final unhandled = <Object>[];
    final echoes = <matrix.Event>[];
    final events = mx.onTimelineEvent.stream.listen(echoes.add);

    late AttachmentSend send;
    await runZonedGuarded(() async {
      composerSend(room, message: 'see below', attachments: [photo]).send();
      send = AttachmentSends.instance.all.single;
      await until(() => send.isFinished);
      // Whatever the SDK still had to say about it.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }, (error, _) => unhandled.add(error));

    expect(unhandled, isEmpty);
    expect(send.stage, AttachmentSendStage.failed);
    // The message says so: its pending event failed, and the app still
    // has its stage for it.
    final txid = send.transactionId!;
    expect(echoes.lastWhere((e) => e.eventId == txid).status.isError, isTrue);
    expect(AttachmentSends.instance.byTransaction(room.localId, txid), send);
    // The text is the photo's caption (Matrix v1.10): it failed with it,
    // and is kept on its failed message.
    expect(transport.sentEvents, isEmpty);
    expect(echoes.lastWhere((e) => e.eventId == txid).content['body'],
        'see below');
    expect(echoes.lastWhere((e) => e.eventId == txid).content['filename'],
        'photo.jpg');
    await events.cancel();
  });

  /// A photo sent while uploads are refused: its send, failed, and its
  /// pending event.
  Future<(AttachmentSend, matrix.Event, List<matrix.Event>)>
      failedPhoto() async {
    transport.failUploads = true;
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    composerSend(room, attachments: [
      PendingFileAttachment(name: 'photo.jpg', data: blackJpeg(400, 300))
    ]).send();
    final send = AttachmentSends.instance.all.single;
    await until(() => send.isFinished);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final failed = echoes.lastWhere((e) => e.eventId == send.transactionId);
    expect(failed.status.isError, isTrue);
    expect(send.stage, AttachmentSendStage.failed);
    return (send, failed, echoes);
  }

  test(
      '"Retry" on a failed file: its stage goes back to uploading, and it '
      'leaves the list once sent', () async {
    final (send, failed, echoes) = await failedPhoto();
    final txid = send.transactionId!;

    // The message menu's "Retry" (timeline_event_menu.dart).
    transport.failUploads = false;
    transport.holdUploads = Completer();
    final before = echoes.length;
    final retry = room.retrySend(room.convertEvent(failed));
    await until(() => echoes
        .skip(before)
        .any((e) => e.eventId == txid && e.status.isSending));
    expect(AttachmentSends.instance.byTransaction(room.localId, txid), send);
    expect(send.stage, AttachmentSendStage.uploading,
        reason: 'not the failure under a message being sent');

    transport.holdUploads!.complete();
    await retry;
    expect(transport.sentEvents, hasLength(1));
    expect(send.stage, AttachmentSendStage.sent);
    expect(AttachmentSends.instance.all, isEmpty,
        reason: 'sent: its bytes are let go');
  });

  test('"Retry" refused again: failed again, and no unhandled error', () async {
    final (send, failed, _) = await failedPhoto();
    final unhandled = <Object>[];
    await runZonedGuarded(() => room.retrySend(room.convertEvent(failed)),
        (error, _) => unhandled.add(error));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(unhandled, isEmpty);
    expect(send.stage, AttachmentSendStage.failed);
    expect(AttachmentSends.instance.all, [send]);
  });

  test('"Cancel" on a failed file takes it off the list', () async {
    final (send, failed, _) = await failedPhoto();
    await room.cancelSend(room.convertEvent(failed));
    expect(AttachmentSends.instance.all, isEmpty);
    expect(
        AttachmentSends.instance
            .byTransaction(room.localId, send.transactionId!),
        isNull);
  });

  for (final fails in [false, true]) {
    test(
        'a file sent in a thread stays in the chat of that thread '
        '${fails ? 'when its upload is refused' : 'while it uploads'}, '
        'until sent', () async {
      if (fails) {
        transport.failUploads = true;
      } else {
        transport.holdUploads = Completer();
      }
      ComposerSend(
        chatRoom: room,
        room: room,
        threads: client.getComponent<ThreadsComponent>(),
        threadId: r'$root',
        message: '',
        attachments: [
          PendingFileAttachment(name: 'photo.jpg', data: blackJpeg(400, 300))
        ],
        interactionType: null,
        interactingEvent: null,
        sendPressed: FileSendTrace.now(),
      ).send();
      final send = AttachmentSends.instance.all.single;
      await until(() => fails ? send.isFinished : send.echoed);
      expect(send.echoed, isTrue);

      // The SDK's pending event has no thread relation, so the thread's
      // timeline does not show it: the thread's chat keeps the file.
      expect(AttachmentSends.instance.inComposerOf(room.localId, r'$root'),
          [send]);
      expect(send.isPicture, isTrue, reason: 'still drawn as a picture');
      expect(send.preview, isNotNull);
      expect(
          AttachmentSends.instance.inComposerOf(room.localId, null), isEmpty);
      if (fails) {
        expect(send.stage, AttachmentSendStage.failed);
      } else {
        transport.holdUploads!.complete();
        await until(() => send.isFinished);
        expect(AttachmentSends.instance.inComposerOf(room.localId, r'$root'),
            isEmpty);
      }
    });
  }

  for (final withPoster in [true, false]) {
    test(
        'a pending video shows ${withPoster ? 'its poster' : 'an empty slot'} '
        'at its size, not a file', () async {
      transport.holdUploads = Completer();
      final poster = blackJpeg(320, 180);
      final video = PendingFileAttachment(
          name: 'clip.mp4', data: Uint8List(2000), mimeType: 'video/mp4')
        ..dimensions = const Size(1280, 720);
      if (withPoster) {
        video
          ..thumbnailFile = poster
          ..thumbnailMime = 'image/jpeg';
      }
      final echoes = <matrix.Event>[];
      final events = mx.onTimelineEvent.stream.listen(echoes.add);
      composerSend(room, attachments: [video]).send();
      final send = AttachmentSends.instance.all.single;
      await until(() => send.echoed);

      final pending = echoes.lastWhere((e) => e.eventId == send.transactionId);
      final message = room.convertEvent(pending) as MatrixTimelineEventMessage;
      final shown = message.attachments!.single as PendingVideoAttachment;
      expect((shown.width, shown.height), (1280.0, 720.0));
      expect(shown.poster, withPoster ? localPicture(poster) : isNull);

      transport.holdUploads!.complete();
      await until(() => send.isFinished);
      await events.cancel();
    });
  }

  testWidgets('the timeline draws a pending video in a slot of its size',
      (tester) async {
    final poster = blackJpeg(32, 18);
    for (final image in [localPicture(poster), null]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: TimelineEventViewAttachments(
                      previewMedia: true,
                      attachments: [
                        PendingVideoAttachment(
                            MemoryFileProvider(Uint8List(4), 'clip.mp4'),
                            name: 'clip.mp4',
                            mimeType: 'video/mp4',
                            poster: image,
                            width: 1280,
                            height: 720)
                      ])))));
      final slot = find.byType(PendingPictureSlot);
      expect(slot, findsOneWidget);
      expect(tester.getSize(slot).height, 200);
      expect(tester.getSize(slot).width, closeTo(200 * 1280 / 720, 0.01));
      expect(find.descendant(of: slot, matching: find.byType(Image)),
          image == null ? findsNothing : findsOneWidget);
    }
  });

  test('a file that cannot be read any more fails where the chat shows it',
      () async {
    final gone = PendingFileAttachment(
        name: 'gone.zip', path: 'unit_test/fixtures/no_such_file.zip');
    composerSend(room, attachments: [gone]).send();
    final send = AttachmentSends.instance.all.single;
    await until(() => send.isFinished);

    expect(send.stage, AttachmentSendStage.failed);
    expect(send.transactionId, isNull);
    expect(AttachmentSends.instance.inComposerOf(room.localId, null), [send]);
  });

  test('a reply uses the event already held: nothing is looked up first',
      () async {
    final held = matrix.Event(
      eventId: r'$held',
      senderId: '@bob:fakeServer.notExisting',
      type: matrix.EventTypes.Message,
      content: {'msgtype': 'm.text', 'body': 'question?'},
      originServerTs: DateTime.now(),
      room: room.matrixRoom,
    );
    final replyTo = room.convertEvent(held);

    await room.sendMessage(message: 'answer', inReplyTo: replyTo);

    expect(transport.seen.where((r) => r.startsWith('GET ')), isEmpty,
        reason: transport.seen.join('\n'));
    final relates =
        transport.sentEvents.single['m.relates_to'] as Map<String, dynamic>;
    expect(relates['m.in_reply_to'], {'event_id': r'$held'});
  });

  test(
      "a reply to an own message still being sent waits for the server's "
      'id: m.in_reply_to never carries the transaction id', () async {
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    transport.holdSends = Completer();
    final pendingSend = room.sendMessage(message: 'not sent yet');
    await until(() => echoes.any((e) => e.status.isSending));
    final pending = echoes.lastWhere((e) => e.status.isSending);
    final txid = pending.eventId;

    final reply = room.sendMessage(
        message: 'answer', inReplyTo: room.convertEvent(pending));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(transport.sentEvents, hasLength(1),
        reason: 'the reply waits for its target to be sent');
    transport.holdSends!.complete();
    await pendingSend;
    await reply;

    final sentTarget =
        echoes.lastWhere((e) => e.transactionId == txid && e.status.isSent);
    final relates = transport.sentEvents.last['m.relates_to'] as Map?;
    print('reply to an own pending message: transaction id $txid, server id '
        '${sentTarget.eventId}, m.relates_to $relates');
    expect(sentTarget.eventId, startsWith(r'$'));
    expect(relates?['m.in_reply_to'], {'event_id': sentTarget.eventId});
    expect(transport.sentEvents.last.toString(), isNot(contains(txid)));
  });

  test(
      'a reply to an own message that failed goes without the relation, '
      'never to its transaction id', () async {
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);
    transport.refuseSends = true;
    await room.sendMessage(message: 'refused').catchError((Object _) => null);
    final failed = echoes.lastWhere((e) => e.status.isError);
    transport.refuseSends = false;

    await room.sendMessage(
        message: 'answer', inReplyTo: room.convertEvent(failed));

    final reply = transport.sentEvents.last;
    expect(reply['body'], 'answer');
    expect(reply['m.relates_to'], isNull);
    expect(reply.toString(), isNot(contains(failed.eventId)));
  });

  test('a file send is a file_send span, without a name of its own', () async {
    final photo = PendingFileAttachment(
        name: 'secret-name.jpg', data: blackJpeg(400, 300))
      ..attachedAt = SpeedLog.instance.now();
    composerSend(room, attachments: [photo]).send();
    final send = AttachmentSends.instance.all.single;
    await until(() => send.isFinished);
    final span = send.trace!.span;

    expect(span.name, SpeedOperation.fileSend);
    expect(span.outcome, SpeedOutcome.ok);
    // The fake homeserver reserves no mxc: the photo goes upload first.
    expect(span.steps.map((s) => s.name), [
      SpeedStep.attached,
      SpeedStep.prepared,
      SpeedStep.uploadFirst,
      SpeedStep.previewPainted,
      SpeedStep.echo,
      SpeedStep.reserve,
      SpeedStep.upload,
      SpeedStep.request,
      SpeedStep.confirmed,
    ]);
    // No frame is drawn in this test: the painted step says unavailable
    // rather than guessing (file_send_report_test.dart draws them).
    expect([
      for (final s in span.steps)
        if (!s.available) s.name
    ], [
      SpeedStep.previewPainted
    ]);
  });
}
