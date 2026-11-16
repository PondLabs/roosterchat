@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/cache/own_media_cache.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import '../speed_log/fake_account.dart';
import 'own_media_fakes.dart';

/// Logging out forgets what the account sent, on native (its entries of
/// the file cache) and on the web (its entries of the map), and nothing
/// else.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appPreparer = ImagePreparer.instance;
  late MediaServer server;
  late MatrixClient client;
  late MatrixRoom room;
  TempFileCache? files;

  Future<void> signIn({required bool native}) async {
    files = native ? TempFileCache() : null;
    fileCache = files;
    server = MediaServer();
    client = await fakeAccount('own_media_logout', server);
    final mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    room = await plainRoom(client);
    await sendPhoto(
        client,
        room,
        PendingFileAttachment(
            name: 'photo.jpg', data: fakeJpegHeader(4032, 3024)));
    await settle();
  }

  setUp(() {
    AttachmentSends.instance.clear();
    ImagePreparer.instance =
        fakePreparer(FakeEngine(width: 4032, height: 3024));
  });

  tearDown(() async {
    ImagePreparer.instance = appPreparer;
    AttachmentSends.instance.clear();
    await client.close();
    await files?.close();
    fileCache = null;
  });

  test('native: logout removes the account\'s own media from the file cache',
      () async {
    await signIn(native: true);
    final own = 'own_media/${client.identifier}/';
    // Someone else's media, and another account's own: they stay.
    await files!.putFile('matrix-mxc://hs/received', Uint8List(3));
    await files!.putFile('own_media/another/mxc://hs/1', Uint8List(3));
    expect(files!.files.keys.where((k) => k.startsWith(own)), hasLength(2));

    await client.logout();

    expect(
        files!.files.keys,
        unorderedEquals(
            ['matrix-mxc://hs/received', 'own_media/another/mxc://hs/1']));
  });

  test('web: logout removes the account\'s own media from the map', () async {
    await signIn(native: false);
    final memory = OwnMediaMemory.instance;
    final other = MemoryOwnMediaCache('another', memory);
    await other.write('mxc://hs/1', Uint8List(3));
    expect(memory.bytes, greaterThan(3));

    await client.logout();

    expect(memory.bytes, 3);
    expect(await other.read('mxc://hs/1'), isNotNull);
    await other.clear();
  });

  test('the session ended by the homeserver clears it too', () async {
    await signIn(native: true);
    // What a soft logout or a revoked token does: the SDK logs out alone.
    await client.getMatrixClient().logout();
    await settle();
    expect(files!.files.keys, isEmpty);
  });
}
