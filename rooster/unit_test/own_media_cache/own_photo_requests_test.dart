@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import '../speed_log/fake_account.dart';
import 'own_media_fakes.dart';

/// One's own photo, once sent, is shown from what this device already
/// holds: in the timeline (its thumbnail) and opened full size, with no
/// media request, on native (the file cache) and on the web's path (no
/// file cache: the in-memory map).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appPreparer = ImagePreparer.instance;

  for (final platform in ['native', 'web']) {
    group('$platform:', () {
      late MediaServer server;
      late MatrixClient client;
      late MatrixRoom room;
      TempFileCache? files;

      setUp(() async {
        AttachmentSends.instance.clear();
        // A 12 MP photo for the preparation: it gets a real thumbnail.
        ImagePreparer.instance =
            fakePreparer(FakeEngine(width: 4032, height: 3024));
        files = platform == 'native' ? TempFileCache() : null;
        fileCache = files;
        server = MediaServer();
        client = await fakeAccount('own_photo_requests', server);
        final mx = client.getMatrixClient();
        mx.backgroundSync = false;
        await mx.oneShotSync();
        room = await plainRoom(client);
      });

      tearDown(() async {
        ImagePreparer.instance = appPreparer;
        AttachmentSends.instance.clear();
        await client.close();
        await files?.close();
        fileCache = null;
      });

      test('the own photo shown in the timeline and full size asks nothing',
          () async {
        final photo = PendingFileAttachment(
            name: 'photo.jpg', data: fakeJpegHeader(4032, 3024));
        final event = await sendPhoto(client, room, photo);
        expect(event.hasThumbnail, isTrue);
        server.mediaRequests.clear();

        final counts = <String, int>{};
        Future<void> count(
            String scenario, Future<void> Function() show) async {
          final before = server.mediaRequests.length;
          await server.countingDownloads(show);
          await settle();
          counts[scenario] = server.mediaRequests.length - before;
        }

        // The timeline: a fresh provider, as a new chat view makes, loads
        // the thumbnail (and the full picture when there is none).
        await count('timeline', () async {
          final picture = timelinePicture(room, event);
          await picture.loadThumbnail?.call();
          if (picture.autoLoadFullRes) await picture.loadFullRes!.call();
        });
        // Opened full size: the lightbox asks the provider for the full
        // picture (lightbox.dart, fetchFullRes).
        await count('full size', () async {
          final picture = timelinePicture(room, event);
          await picture.loadFullRes!.call();
        });
        // Saved or opened as a file: the attachment's file.
        await count('file', () async {
          await timelineFileData(room, event);
        });

        printOnFailure('media requests by scenario: $counts');
        // ignore: avoid_print
        print('$platform media requests by scenario: $counts');
        expect(counts, {'timeline': 0, 'full size': 0, 'file': 0});
      });

      test('what the timeline shows is the photo sent: thumbnail and original',
          () async {
        final data = fakeJpegHeader(4032, 3024);
        final photo = PendingFileAttachment(name: 'photo.jpg', data: data);
        final event = await sendPhoto(client, room, photo);
        final thumbnailSize = event.thumbnailInfoMap['size'] as int;
        expect(thumbnailSize, lessThan(data.length));

        final picture = timelinePicture(room, event);
        expect((await picture.loadThumbnail!.call())!.length, thumbnailSize);
        expect(await picture.loadFullRes!.call(), data);
        expect(server.mediaRequests, isEmpty);
        expect(event.senderId, client.getMatrixClient().userID);
        expect(event.status, isNot(matrix.EventStatus.sending));
      });
    });
  }
}
