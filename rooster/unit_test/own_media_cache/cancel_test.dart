@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import '../pending_media/matrix_fakes.dart';
import '../speed_log/fake_account.dart';
import 'own_media_fakes.dart';

/// A photo taken away ("Cancel") after its upload: its files leave the own
/// media at once, not at logout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appPreparer = ImagePreparer.instance;
  late MediaServer server;
  late MatrixClient client;
  late MatrixRoom room;
  late TempFileCache files;

  setUp(() async {
    AttachmentSends.instance.clear();
    ImagePreparer.instance =
        fakePreparer(FakeEngine(width: 4032, height: 3024));
    files = TempFileCache();
    fileCache = files;
    server = MediaServer();
    client = await fakeAccount('own_media_cancel', server);
    final mx = client.getMatrixClient();
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

  test('cancelled after the upload: both files leave the own media', () async {
    final mx = client.getMatrixClient();
    final hold = Completer<void>();
    server.holdNextSend = hold.future;
    final echoes = <matrix.Event>[];
    final events = mx.onTimelineEvent.stream.listen(echoes.add);
    composerSend(room, attachments: [
      PendingFileAttachment(name: 'photo.jpg', data: fakeJpegHeader(4032, 3024))
    ]).send();
    final send = AttachmentSends.instance.all.single;
    await until(() => send.stage == AttachmentSendStage.sending);
    await ownMediaOnDisk(files, client.identifier, 2);
    final pending = echoes.lastWhere(
        (e) => e.eventId == send.transactionId && e.content['url'] is String);

    await room.cancelSend(room.convertEvent(pending));
    await ownMediaOnDisk(files, client.identifier, 0);

    // Whatever the SDK still does with the send, nothing comes back.
    hold.complete();
    await settle();
    await events.cancel();
    expect(files.files.keys.where((k) => k.startsWith('own_media/')), isEmpty);
  });
}
