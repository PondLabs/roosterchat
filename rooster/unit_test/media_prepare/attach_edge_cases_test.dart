import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/attachment.dart';
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
}
