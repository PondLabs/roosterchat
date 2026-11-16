@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
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
    // The text went on its own.
    expect(transport.sentEvents.map((e) => e['body']), ['see below']);
    await events.cancel();
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
    expect(span.steps.map((s) => s.name), [
      SpeedStep.attached,
      SpeedStep.prepared,
      SpeedStep.previewPainted,
      SpeedStep.echo,
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
