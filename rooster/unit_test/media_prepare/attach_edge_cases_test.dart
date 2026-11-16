import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import 'fakes.dart';

/// Attaching files the preparation must leave alone or survive.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync("t22_attach"));
  tearDown(() => dir.deleteSync(recursive: true));

  ImagePreparer preparer() =>
      ImagePreparer(encoder: FakeEncoder(), log: SpeedLog(frames: NoFrames()));

  test("a file that is not a picture is not read when it is attached",
      () async {
    final file = File("${dir.path}/clip.mp4")
      ..writeAsBytesSync(Uint8List(2 * 1000 * 1000));
    final attachment = PendingFileAttachment(
        name: "clip.mp4", path: file.path, size: 2 * 1000 * 1000);
    expect(attachment.mimeType, "video/mp4");

    await attachment.startImagePreparation(preparer: preparer());
    expect(attachment.data, isNull, reason: "read at Send, as before");

    await attachment.resolve(); // what Send does
    expect(attachment.data, hasLength(2 * 1000 * 1000));
  });

  test("a picture that cannot be read when attached: no error, Send reads it",
      () async {
    final bytes = File("unit_test/fixtures/image_metadata/orientation_6.jpg")
        .readAsBytesSync();
    final file = File("${dir.path}/photo.jpg")..writeAsBytesSync(bytes);
    final lock = file.openSync(mode: FileMode.append)
      ..lockSync(FileLock.exclusive);
    final attachment =
        PendingFileAttachment(name: "photo.jpg", path: file.path);

    // chat.dart does not wait for this future: it must not end in error.
    await expectLater(
        attachment.startImagePreparation(preparer: preparer()), completes);
    expect(attachment.data, isNull);

    lock
      ..unlockSync()
      ..closeSync();
    await attachment.resolve(); // Send, once the file can be read
    final prepared = await attachment.imagePreparation(preparer: preparer());
    expect((prepared!.width, prepared.height), (48, 64));
  });

  test("a thumbnail no smaller than the file sent is left out", () async {
    // A flat screenshot: 4.8 MB as BMP, a few kB once sent as PNG.
    final picture = img.Image(width: 1600, height: 1000);
    img.fill(picture, color: img.ColorRgb8(245, 245, 245));
    for (var i = 0; i < 12; i++) {
      img.fillRect(picture,
          x1: 60,
          y1: 40 + i * 70,
          x2: 900 + i * 40,
          y2: 70 + i * 70,
          color: img.ColorRgb8(40, 40, 60));
    }
    final bmp = img.encodeBmp(picture);
    final attachment =
        PendingFileAttachment(name: "shot.bmp", data: bmp, size: bmp.length);
    final processed = (await matrixFilesForAttachment(attachment,
        preparer: ImagePreparer(log: SpeedLog(frames: NoFrames()))))!;

    expect(processed.file.mimeType, "image/png");
    expect(processed.thumbnailFile, isNull,
        reason: "the PNG is ${processed.file.bytes.length} bytes");
    expect(processed.file, isA<PreparedImageFile>(),
        reason: "an m.image the SDK makes no thumbnail for");
    expect((processed.file.info["w"], processed.file.info["h"]), (1600, 1000));
  });
}
