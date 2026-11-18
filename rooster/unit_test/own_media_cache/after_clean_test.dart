@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_mxc_file_provider.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import '../speed_log/fake_account.dart';
import 'own_media_fakes.dart';

/// The file cache's 5 day clean took the own photo's entries: opening or
/// showing it asks the network again, and what comes back is kept in the
/// account's own media again, not under the keys every account shares,
/// so logging out still leaves nothing of it on disk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appPreparer = ImagePreparer.instance;
  late MediaServer server;
  late MatrixClient client;
  late MatrixRoom room;
  late TempFileCache files;
  late matrix.Event event;

  setUp(() async {
    AttachmentSends.instance.clear();
    ImagePreparer.instance =
        fakePreparer(FakeEngine(width: 4032, height: 3024));
    files = TempFileCache();
    fileCache = files;
    server = MediaServer();
    client = await fakeAccount('own_media_after_clean', server);
    final mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    room = await plainRoom(client);
    event = await sendPhoto(
        client,
        room,
        PendingFileAttachment(
            name: 'photo.jpg', data: fakeJpegHeader(4032, 3024)));
    await ownMediaOnDisk(files, client.identifier, 2);
    // What the 5 day clean does to entries not read since.
    await files.removeFilesStartingWith('own_media/');
    server.mediaRequests.clear();
  });

  tearDown(() async {
    ImagePreparer.instance = appPreparer;
    AttachmentSends.instance.clear();
    await client.close();
    await files.close();
    fileCache = null;
  });

  Iterable<String> sharedKeys() =>
      files.files.keys.where((k) => !k.startsWith('own_media/'));

  test('opened as a file: from the network, back into the own media', () async {
    final provider = MxcFileProvider(
        client.getMatrixClient(), event.attachmentMxcUrl!,
        event: event);
    final uri = await provider.resolve();
    final firstRequests = server.mediaRequests.length;
    // Opened again: from the own media.
    await provider.resolve();

    // ignore: avoid_print
    print('after the clean, opened twice: media requests '
        '${server.mediaRequests.length}; keys ${files.files.keys.toList()}');
    expect(uri, isNotNull);
    expect(File.fromUri(uri!).readAsBytesSync(), server.served);
    expect(firstRequests, 1);
    expect(server.mediaRequests, hasLength(1));
    expect(files.files.keys,
        ['own_media/${client.identifier}/${event.attachmentMxcUrl}']);
    expect(sharedKeys(), isEmpty);

    await client.logout();
    // ignore: avoid_print
    print('after logout: keys ${files.files.keys.toList()}');
    expect(files.files, isEmpty);
    expect(File.fromUri(uri).existsSync(), isFalse);
  });

  test('shown in the timeline and full size: back into the own media',
      () async {
    final picture = timelinePicture(room, event);
    await picture.loadThumbnail!.call();
    await picture.loadFullRes!.call();
    await settle();

    // ignore: avoid_print
    print('after the clean, shown: media requests '
        '${server.mediaRequests.length}; keys ${files.files.keys.toList()}');
    expect(server.mediaRequests, hasLength(2));
    expect(sharedKeys(), isEmpty);
    expect(files.files.keys, hasLength(2));

    // Shown again by a new chat view: nothing asked.
    final again = timelinePicture(room, event);
    await again.loadThumbnail!.call();
    await again.loadFullRes!.call();
    expect(server.mediaRequests, hasLength(2));

    await client.logout();
    expect(files.files, isEmpty);
  });
}
