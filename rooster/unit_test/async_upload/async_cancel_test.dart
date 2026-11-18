// "Cancel send" on a photo whose event was sent and whose upload runs, a
// redaction that fails, and the photo's file_send span in the speed log.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/media/async_photo_send.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/client/matrix/media/own_media.dart';
import 'package:rooster/diagnostic/speed_log/file_send_trace.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/text_send_trace.dart';

import '../speed_log/fake_account.dart';
import 'async_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AsyncTransport transport;
  late MatrixClient client;
  late MatrixRoom room;
  late matrix.Room mxRoom;
  var n = 0;

  setUp(() async {
    TextSendTrace.nextFrameDrawn = () async => false;
    AttachmentSends.instance.clear();
    transport = AsyncTransport();
    client = await fakeAccount('async_cancel_${n++}', transport);
    final mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    room = await plainRoom(client);
    mxRoom = room.matrixRoom;
    SpeedLog.instance.spans.clear();
  });

  tearDown(() async {
    AttachmentSends.instance.clear();
    await client.close();
  });

  /// The sent event of [attachment]'s photo, once its uploads are held.
  Future<matrix.Event> sentWhileUploading(
      TrackedMatrixAttachment attachment) async {
    await until(() => transport.puts.length == 2);
    final txid = attachment.send.transactionId!;
    final photo = asyncPhotoSendOf(mxRoom, txid)!;
    expect(photo.uploading, isTrue);
    return (await mxRoom.getEventById(photo.eventId!))!;
  }

  test(
      'Cancel send during the uploads aborts them, takes the message back, '
      'and no upload goes on', () async {
    transport.holdPuts = true;
    final attachment = photo();
    final sending = sendAttachment(mxRoom, attachment);
    final sent = await sentWhileUploading(attachment);
    expect(sent.status, matrix.EventStatus.sent);
    // The SDK says it can be cancelled although its request left.
    expect(mxRoom.canCancelSend(sent.transactionId!), isTrue);

    await room.cancelSend(room.convertEvent(sent));
    expect(await sending, isNull);

    expect(transport.abortedPuts, 2);
    expect(transport.answeredPuts, 0);
    expect(transport.log.last, 'PUT redact');
    expect(AttachmentSends.instance.all, isEmpty);
    expect(asyncPhotoSendOfEvent(sent), isNull);
    expect(mxRoom.canCancelSend(sent.transactionId!), isFalse);

    // Nothing starts again, released or not.
    transport.releasePuts.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transport.puts, hasLength(2));
    expect(transport.answeredPuts, 0);
  });

  test(
      'a redaction that fails leaves the message in the room, its sender '
      'told so under it, and a failed message to retry', () async {
    transport.holdPuts = true;
    transport.failRedacts = true;
    final attachment = photo();
    final sending = sendAttachment(mxRoom, attachment);
    final sent = await sentWhileUploading(attachment);

    await room.cancelSend(room.convertEvent(sent));
    expect(await sending, isNull);
    expect(transport.log.last, 'PUT redact');
    expect(isPhotoLeftInRoom(sent), isTrue);
    expect(attachment.send.stage, AttachmentSendStage.failed);
    final failed = failedPhoto(mxRoom, attachment.send);
    expect(failed, isNotNull);
    expect((await shown(mxRoom, failed!.failedMessageId!))!.status,
        matrix.EventStatus.error);
  });

  test('Cancel on the failed message takes it away and lets the photo go',
      () async {
    transport.onPut = (body, _) async => json(403, {'errcode': 'M_FORBIDDEN'});
    final attachment = photo();
    expect(await sendAttachment(mxRoom, attachment), isNull);
    final failed = failedPhoto(mxRoom, attachment.send)!;
    final id = failed.failedMessageId!;
    final message = (await shown(mxRoom, id))!;

    await room.cancelSend(room.convertEvent(message));
    expect(await shown(mxRoom, id), isNull);
    expect(asyncPhotoSendOf(mxRoom, id), isNull);
    expect(mxRoom.sendingFilePlaceholders[id], isNull);
    expect(AttachmentSends.instance.all, isEmpty);
  });

  test(
      'the own media gets the photo once it is up, never while it goes up '
      'or when its upload fails', () async {
    final mx = client.getMatrixClient();
    final own = ownMediaOf(mx)!;
    transport.holdPuts = true;
    final attachment = photo();
    final sending = sendAttachment(mxRoom, attachment);
    final sent = await sentWhileUploading(attachment);
    final key = sent.attachmentMxcUrl.toString();
    expect(await readOwnMedia(mx, sent), attachment.file.bytes,
        reason: 'from memory while it goes up');
    expect(await own.read(key), isNull);

    transport.releasePuts.complete();
    expect(await sending, isNotNull);
    expect(await own.read(key), attachment.file.bytes);
    expect(await own.read(sent.thumbnailMxcUrl.toString()),
        attachment.thumbnailFile!.bytes);

    transport.onPut = (body, _) async => json(403, {'errcode': 'M_FORBIDDEN'});
    transport.holdPuts = false;
    final failing = photo(seed: 2);
    expect(await sendAttachment(mxRoom, failing), isNull);
    expect(await own.read('mxc://fakeserver.notexisting/r3'), isNull);
    expect(await own.read('mxc://fakeserver.notexisting/r4'), isNull);
  });

  test(
      'file_send says the photo went by asynchronous upload, with its '
      'reservations, its event and its uploads', () async {
    final trace = FileSendTrace.start(sendPressed: FileSendTrace.now());
    final attachment = photo();
    final send =
        AttachmentSend(roomKey: room.localId, attachment: null, trace: trace);
    expect(
        await sendAttachment(
            mxRoom,
            TrackedMatrixAttachment(attachment.file, send,
                thumbnailFile: attachment.thumbnailFile)),
        isNotNull);

    final steps = trace.span.steps.map((s) => s.name).toList();
    print('file_send steps, asynchronous upload: $steps');
    expect(trace.span.outcome, SpeedOutcome.ok);
    expect(steps, contains(SpeedStep.asyncUpload));
    expect(steps, isNot(contains(SpeedStep.uploadFirst)));
    expect(steps.where((s) => s == SpeedStep.reserve), hasLength(2));
    expect(steps.where((s) => s == SpeedStep.upload), hasLength(2));
    expect(steps, containsAll([SpeedStep.confirmed, SpeedStep.uploaded]));
    final confirmed =
        trace.span.steps.firstWhere((s) => s.name == SpeedStep.confirmed);
    final uploaded =
        trace.span.steps.firstWhere((s) => s.name == SpeedStep.uploaded);
    expect(confirmed.duration!, lessThanOrEqualTo(uploaded.duration!));
  });

  test('file_send says a photo without a reservation went upload first',
      () async {
    transport.onCreate = (_) => json(404, {'errcode': 'M_UNRECOGNIZED'});
    final trace = FileSendTrace.start(sendPressed: FileSendTrace.now());
    final attachment = photo();
    final send =
        AttachmentSend(roomKey: room.localId, attachment: null, trace: trace);
    expect(
        await sendAttachment(
            mxRoom,
            TrackedMatrixAttachment(attachment.file, send,
                thumbnailFile: attachment.thumbnailFile)),
        isNotNull);

    final steps = trace.span.steps.map((s) => s.name).toList();
    print('file_send steps, upload first: $steps');
    expect(steps, contains(SpeedStep.uploadFirst));
    expect(steps, isNot(contains(SpeedStep.asyncUpload)));
    expect(steps, isNot(contains(SpeedStep.uploaded)));
    expect(steps.where((s) => s == SpeedStep.reserve), hasLength(1));
  });
}
