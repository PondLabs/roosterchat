@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_mxc_image_provider.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/media/own_media.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import '../pending_media/matrix_fakes.dart';
import '../speed_log/fake_account.dart';
import 'own_media_fakes.dart';

/// What the cache keeps as a sent photo's thumbnail is its real thumbnail,
/// never the whole file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appPreparer = ImagePreparer.instance;
  late MediaServer server;
  late MatrixClient client;
  late matrix.Client mx;
  late MatrixRoom room;
  late TempFileCache files;

  setUp(() async {
    AttachmentSends.instance.clear();
    ImagePreparer.instance =
        fakePreparer(FakeEngine(width: 4032, height: 3024));
    files = TempFileCache();
    fileCache = files;
    server = MediaServer();
    client = await fakeAccount('own_media_thumbnail', server);
    mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    room = await plainRoom(client);
  });

  tearDown(() async {
    ImagePreparer.instance = appPreparer;
    AttachmentSends.instance.clear();
    await client.close();
    await files.close();
    fileCache = null;
  });

  test('the thumbnail entry is the thumbnail sent, the original the photo',
      () async {
    final data = fakeJpegHeader(4032, 3024);
    final event = await sendPhoto(
        client, room, PendingFileAttachment(name: 'photo.jpg', data: data));
    await ownMediaOnDisk(files, client.identifier, 2);

    final prefix = 'own_media/${client.identifier}/';
    final thumbnailSize = event.thumbnailInfoMap['size'] as int;
    // The thumbnail uploaded is the one the preparation made (10 bytes).
    expect(server.uploadSizes, unorderedEquals([data.length, thumbnailSize]),
        reason: 'the file and its thumbnail can go up together');
    expect(files.sizes, {
      '$prefix${event.attachmentMxcUrl}': data.length,
      '$prefix${event.thumbnailMxcUrl}': thumbnailSize,
    });
    expect(thumbnailSize, lessThan(data.length ~/ 1000));
  });

  test(
      'a pending photo shown by the picture provider does not store the '
      'whole file as its thumbnail', () async {
    final data = fakeJpegHeader(4032, 3024);
    final hold = Completer<void>();
    server.holdNextSend = hold.future;
    final echoes = <matrix.Event>[];
    final events = mx.onTimelineEvent.stream.listen(echoes.add);
    composerSend(room,
            attachments: [PendingFileAttachment(name: 'photo.jpg', data: data)])
        .send();
    final send = AttachmentSends.instance.all.single;
    await until(() => send.stage == AttachmentSendStage.sending);
    final pending = echoes.lastWhere(
        (e) => e.eventId == send.transactionId && e.content['url'] is String);
    expect(pending.status.isSending, isTrue);

    // Without the own media (say it was cleared), the provider falls back
    // to the SDK, which answers a pending event with the whole file.
    await ownMediaOf(mx)!.clear();
    final shown = await MatrixMxcImage.loadMatrixThumbnail(
        mx, pending.attachmentMxcUrl!, pending);
    await settle();
    expect(shown!.length, data.length);
    expect(
        files.files.keys,
        isNot(contains(
            MatrixMxcImage.getThumbnailIdentifier(pending.attachmentMxcUrl!))));

    hold.complete();
    await until(() => send.isFinished);
    await events.cancel();
  });
}
