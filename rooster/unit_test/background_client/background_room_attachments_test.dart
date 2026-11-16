import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/database.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_attachment.dart';
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/client/matrix_background/matrix_background_client.dart';
import 'package:rooster/client/matrix_background/matrix_background_room.dart';

import '../media_prepare/fakes.dart';
import '../media_prepare/send_harness.dart';

/// A picture sent from the Android background client's room goes through
/// the picture's one preparation, as from the app's own rooms: one decode,
/// at a reduced size, and the SDK decodes nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SendHarness harness;
  setUp(() async => harness = await SendHarness.start(Stopwatch()..start()));
  tearDown(() => harness.dispose());

  MatrixBackgroundRoom backgroundRoom(FakeEngine engine) =>
      MatrixBackgroundRoom(
        MatrixBackgroundClient(databaseId: 'attachments'),
        roomId: '!1234:fakeServer.notExisting',
        data: const RoomDataData(
            roomId: '!1234:fakeServer.notExisting', content: '{}'),
        preloadState: const [],
        nonPreloadState: const [],
        imagePreparer: fakePreparer(engine),
      );

  PendingFileAttachment photo() {
    final bytes = fakeJpegHeader(4032, 3024);
    return PendingFileAttachment(
        name: 'photo.jpg', data: bytes, size: bytes.length);
  }

  test('a photo: one decode at 800 px; w, h and thumbnail as in the app',
      () async {
    final engine = FakeEngine(width: 4032, height: 3024);
    final processed =
        await backgroundRoom(engine).processAttachments([photo()]);

    // Decoded once, on its long side, at thumbnail size.
    expect(engine.calls, hasLength(1));
    final decode = engine.calls.single;
    expect((decode.targetWidth, decode.targetHeight), (800, null));

    final files = processed.single as MatrixProcessedAttachment;
    await harness.room
        .sendFileEvent(files.file, thumbnail: files.thumbnailFile);
    expect(harness.sdkImagePasses, 0, reason: 'the SDK decoded nothing');

    final content = harness.transport.sentEvents.single;
    expect(content['msgtype'], matrix.MessageTypes.Image);
    final info = content['info'] as Map<String, dynamic>;
    expect((info['w'], info['h']), (4032, 3024));
    expect(info['xyz.amorgan.blurhash'], isA<String>());
    final thumbnailInfo = info['thumbnail_info'] as Map<String, dynamic>;
    expect((thumbnailInfo['w'], thumbnailInfo['h']), (800, 600));
    expect(thumbnailInfo['mimetype'], 'image/jpeg');
    expect(info['thumbnail_url'], startsWith('mxc://'));

    // The app's own room makes the same files of the same picture.
    final app = (await matrixFilesForAttachment(photo(),
        preparer: fakePreparer(FakeEngine(width: 4032, height: 3024))))!;
    expect(files.file.info, app.file.info);
    expect(files.thumbnailFile?.info, app.thumbnailFile?.info);
  });

  test('a file that cannot be read is left out', () async {
    final engine = FakeEngine();
    final processed = await backgroundRoom(engine).processAttachments(
        [PendingFileAttachment(path: 'unit_test/background_client/gone.jpg')]);
    expect(processed, isEmpty);
    expect(engine.calls, isEmpty);
  });
}
