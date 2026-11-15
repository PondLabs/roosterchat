import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import 'fakes.dart';
import 'pictures.dart';
import 'send_harness.dart';

/// From attach to the event on the (fake) homeserver: the picture is
/// decoded once, by the engine, at a reduced size, and the Matrix SDK runs
/// none of its own image passes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fixtures = "unit_test/fixtures/image_metadata";

  late SendHarness harness;
  late CountingEngine engine;
  late ImagePreparer preparer;
  setUp(() async {
    harness = await SendHarness.start(Stopwatch()..start());
    engine = CountingEngine();
    preparer = ImagePreparer(
        codecFactory: engine.codec, log: SpeedLog(frames: NoFrames()));
  });
  tearDown(() => harness.dispose());

  /// Attach (the preparation starts), then Send as `MatrixRoom` does.
  Future<Map<String, dynamic>> attachAndSend(Uint8List bytes,
      {String name = "photo.jpg", String? mimeType}) async {
    final attachment = PendingFileAttachment(
        name: name, data: bytes, mimeType: mimeType, size: bytes.length);
    final attached = attachment.startImagePreparation(preparer: preparer);
    final processed =
        (await matrixFilesForAttachment(attachment, preparer: preparer))!;
    await attached;
    await harness.room
        .sendFileEvent(processed.file, thumbnail: processed.thumbnailFile);
    return harness.transport.sentEvents.single;
  }

  test("a large photo: one decode, by the engine, at 800 px; no SDK pass",
      () async {
    final bytes = largeJpegWithExifOf(
        File("$fixtures/orientation_6.jpg").readAsBytesSync());
    final content = await attachAndSend(bytes);

    expect(engine.decodes, [(null, 800)],
        reason: "one decode, the long side (height as displayed) at 800");
    expect(harness.sdkImagePasses, 0);

    expect(content["msgtype"], "m.image");
    final info = content["info"] as Map<String, dynamic>;
    expect((info["w"], info["h"]), (1500, 2000),
        reason: "as displayed: stored 2000 x 1500 with orientation 6");
    expect(info["xyz.amorgan.blurhash"], isA<String>());
    expect(info["mimetype"], "image/jpeg");
    expect(info["size"], bytes.length);
    final thumbnailInfo = info["thumbnail_info"] as Map<String, dynamic>;
    expect(thumbnailInfo["mimetype"], "image/jpeg");
    expect((thumbnailInfo["w"], thumbnailInfo["h"]), (600, 800));
    expect(info["thumbnail_url"], startsWith("mxc://"));

    // What went up: the photo as it was, and the thumbnail it describes.
    final uploads = harness.transport.uploads;
    expect(uploads, hasLength(2));
    expect(uploads[0].bytes, bytes);
    expect(uploads[1].bytes.length, thumbnailInfo["size"]);
    final codec = await ui.instantiateImageCodec(uploads[1].bytes);
    final thumbnail = (await codec.getNextFrame()).image;
    expect((thumbnail.width, thumbnail.height), (600, 800));
    thumbnail.dispose();
    codec.dispose();
  });

  for (final orientation in [6, 8]) {
    test(
        "orientation $orientation fixture: w and h as displayed, no thumbnail "
        "and no SDK thumbnail pass", () async {
      final bytes =
          File("$fixtures/orientation_$orientation.jpg").readAsBytesSync();
      final content = await attachAndSend(bytes);

      expect(engine.decodes, hasLength(1));
      expect(harness.sdkImagePasses, 0,
          reason: "the SDK made no thumbnail of its own");
      expect(content["msgtype"], "m.image");
      final info = content["info"] as Map<String, dynamic>;
      expect((info["w"], info["h"]), (48, 64), reason: "SOF is 64 x 48");
      expect(info["xyz.amorgan.blurhash"], isA<String>());
      expect(info.containsKey("thumbnail_info"), isFalse);
      expect(info.containsKey("thumbnail_url"), isFalse);
      expect(harness.transport.uploads, hasLength(1));
    });
  }

  test("a source over 800 px but under 300 kB goes without a thumbnail",
      () async {
    final bytes = noisyPng(1000, 80, transparent: false);
    expect(bytes.length, lessThan(thumbnailMinSourceBytes));
    final content = await attachAndSend(bytes, name: "wide.png");
    final info = content["info"] as Map<String, dynamic>;
    expect((info["w"], info["h"]), (1000, 80));
    expect(info.containsKey("thumbnail_info"), isFalse);
    expect(harness.sdkImagePasses, 0);
    expect(engine.decodes, [(64, null)], reason: "only for the blurhash");
  });

  test("the preparation started at attach is the one Send uses", () async {
    final bytes = File("$fixtures/orientation_6.jpg").readAsBytesSync();
    final attachment =
        PendingFileAttachment(name: "a.jpg", data: bytes, size: bytes.length);
    await attachment.startImagePreparation(preparer: preparer);
    expect(engine.decodes, hasLength(1));
    await matrixFilesForAttachment(attachment, preparer: preparer);
    await matrixFilesForAttachment(attachment, preparer: preparer);
    expect(engine.decodes, hasLength(1), reason: "reused, not redone");
  });

  test("a picture the engine cannot decode goes as a plain file", () async {
    final bytes = File("$fixtures/truncated_undecodable.jpg").readAsBytesSync();
    final content = await attachAndSend(bytes, name: "broken.jpg");
    expect(content["msgtype"], matrix.MessageTypes.File);
    expect((content["info"] as Map)["mimetype"], "application/octet-stream");
    expect(harness.sdkImagePasses, 0);
  });
}
