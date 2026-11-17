import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/utils/image/image_header.dart';
import 'package:rooster/utils/image/metadata/image_container.dart';
import 'package:rooster/utils/image/metadata/remove_image_metadata.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import '../media_prepare/send_harness.dart';
import 'photos.dart';

/// From the attach dialog's output to the event on the (fake) homeserver,
/// with the engine and the encoder of the app: a photo over 2,560 px goes
/// reduced, anything else goes as the attach dialog left it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SendHarness harness;
  late CountingEngine engine;
  late SpeedLog log;
  late ImagePreparer preparer;
  setUp(() async {
    harness = await SendHarness.start(Stopwatch()..start());
    engine = CountingEngine();
    log = SpeedLog(frames: NoFrames());
    preparer = ImagePreparer(codecFactory: engine.codec, log: log);
  });
  tearDown(() => harness.dispose());

  /// What the attach dialog attaches for [original] with "Send original"
  /// off: the picture without its metadata, to be reduced.
  Future<PendingFileAttachment> attached(Uint8List original,
      {String name = "photo.jpg"}) async {
    final removal = await removeImageMetadata(original);
    final bytes = removal.bytes!;
    return PendingFileAttachment(
        name: name, data: bytes, size: bytes.length, mimeType: removal.mimeType)
      ..reducePhoto = true;
  }

  /// Attach (the preparation starts), then Send as `MatrixRoom` does: the
  /// event's content and the file uploaded.
  Future<(Map<String, dynamic>, Uint8List)> send(
      PendingFileAttachment attachment) async {
    final started = attachment.startImagePreparation(preparer: preparer);
    final processed =
        (await matrixFilesForAttachment(attachment, preparer: preparer))!;
    await started;
    await harness.room
        .sendFileEvent(processed.file, thumbnail: processed.thumbnailFile);
    return (
      harness.transport.sentEvents.single,
      harness.transport.uploads.first.bytes,
    );
  }

  /// No metadata a reader finds, and nothing a rewrite would remove: only
  /// JFIF's APP0, the tables, the frame and the scan.
  Future<void> expectBareJpeg(Uint8List bytes) async {
    expect(await readExifFromBytes(bytes), isEmpty);
    expect(parseImageContainer(bytes)!.withoutMetadata(), bytes);
    final markers = jpegMarkersBeforeScan(bytes);
    expect(markers.where((m) => m >= 0xE1 && m <= 0xEF), isEmpty,
        reason: "no APP1 to APP15 (Exif, XMP, ICC, MPF…): $markers");
    expect(markers.where((m) => m == 0xFE), isEmpty, reason: "no comment");
    expect(readImageHeader(bytes)!.orientation, 1,
        reason: "upright pixels, no orientation tag");
  }

  test(
      "the 12 MP photo goes as a 2,560 x 1,920 JPEG under 1.5 MB, with no "
      "metadata, its GPS included",
      skip: sampleDir == null
          ? "set SPEED_SAMPLE_DIR to the folder with photo12mp.jpg"
          : null, () async {
    final photo = File("$sampleDir/photo12mp.jpg").readAsBytesSync();
    expect(readImageHeader(photo)!.width, 4032);
    // A camera's photo: its Exif with GPS.
    final original = withExifOf(photo, fixture("gps_exif.jpg"));
    expect(
        (await readExifFromBytes(original)).keys.any((k) => k.contains("GPS")),
        isTrue);

    final (content, uploaded) = await send(await attached(original));

    expect(engine.decodes, [(2560, null)], reason: "one decode, at 2,560");
    expect(harness.sdkImagePasses, 0);
    final info = content["info"] as Map<String, dynamic>;
    expect((info["w"], info["h"]), (2560, 1920));
    expect(info["mimetype"], "image/jpeg");
    expect(info["size"], uploaded.length);
    expect(readImageHeader(uploaded)!.mimeType, "image/jpeg");
    final decoded = await engineDecode(uploaded);
    expect((decoded.$1, decoded.$2), (2560, 1920));
    expect(uploaded.length, lessThan(1500 * 1000));
    await expectBareJpeg(uploaded);
    final thumbnailInfo = info["thumbnail_info"] as Map<String, dynamic>;
    expect((thumbnailInfo["w"], thumbnailInfo["h"]), (800, 600));

    final reduce = log.spans
        .toList()
        .single
        .steps
        .firstWhere((s) => s.name == SpeedStep.reduce);
    expect(reduce.values[SpeedValue.bytes], uploaded.length);

    // ignore: avoid_print
    print("photo12mp.jpg: ${original.length} bytes attached, "
        "${uploaded.length} bytes sent, ${decoded.$1} x ${decoded.$2}; "
        "segments ${jpegMarkersBeforeScan(uploaded).map((m) => m.toRadixString(16)).join(" ")}");
    final out = Platform.environment["PHOTO_REDUCE_OUT"];
    if (out != null) {
      File("$out/photo12mp-reduced.jpg").writeAsBytesSync(uploaded);
    }
  });

  for (final (orientation, displayed) in [
    (6, (1707, 2560)),
    (8, (1707, 2560)),
  ]) {
    test(
        "orientation $orientation: sent upright, the event's w and h those "
        "of the picture sent", () async {
      // Stored 2700 x 1800, shown 1800 x 2700 (a portrait photo).
      final original = withExifOf(
          cornerJpeg(2700, 1800), fixture("orientation_$orientation.jpg"));
      expect(readImageHeader(original)!.orientation, orientation);
      final asShown = await engineDecode(original, targetWidth: 300);
      expect((asShown.$1, asShown.$2), (300, 450),
          reason: "the engine turns it upright");

      final (content, uploaded) = await send(await attached(original));

      final info = content["info"] as Map<String, dynamic>;
      expect((info["w"], info["h"]), displayed);
      final header = readImageHeader(uploaded)!;
      expect((header.width, header.height), displayed);
      final sent = await engineDecode(uploaded);
      expect((sent.$1, sent.$2), displayed);
      await expectBareJpeg(uploaded);
      // The same picture the engine shows for the original, corner by
      // corner.
      for (final (fx, fy) in [(0.05, 0.05), (0.95, 0.05), (0.05, 0.95)]) {
        expect(near(colourAt(sent, fx, fy), colourAt(asShown, fx, fy)), isTrue,
            reason: "at ($fx, $fy): sent ${colourAt(sent, fx, fy)}, "
                "shown ${colourAt(asShown, fx, fy)}");
      }
      final thumbnailInfo = info["thumbnail_info"] as Map<String, dynamic>;
      expect((thumbnailInfo["w"], thumbnailInfo["h"]), (533, 800));
    });
  }

  group("sent as the attach dialog left it, not encoded again:", () {
    /// Sends [original] through the dialog's removal and the preparation
    /// with reduce on, and checks what goes up is the removal's output, the
    /// same pixels as the original.
    Future<void> expectNotReencoded(Uint8List original, String name) async {
      final attachment = await attached(original, name: name);
      final dialogOutput = attachment.data!;
      final (content, uploaded) = await send(attachment);
      expect(uploaded, dialogOutput);
      final sent = await engineDecode(uploaded);
      final source = await engineDecode(original);
      expect((sent.$1, sent.$2), (source.$1, source.$2));
      expect(sent.$3, source.$3, reason: "the same pixels");
      final info = content["info"] as Map<String, dynamic>;
      expect((info["w"], info["h"]), (source.$1, source.$2));
      expect(log.spans.toList().single.steps.map((s) => s.name),
          isNot(contains(SpeedStep.reduce)));
      expect(engine.decodes.single, isNot((2560, null)));
    }

    test("a JPEG of 2,000 px", () async {
      await expectNotReencoded(
          withExifOf(cornerJpeg(2000, 1500), fixture("gps_exif.jpg")),
          "photo.jpg");
    });

    test("a PNG with transparency", () async {
      final image = img.Image(width: 2700, height: 400, numChannels: 4);
      for (var y = 0; y < 400; y++) {
        for (var x = 0; x < 2700; x++) {
          image.setPixelRgba(x, y, x % 256, y % 256, 90, x < 600 ? 0 : 255);
        }
      }
      await expectNotReencoded(img.encodePng(image), "picture.png");
    });

    test("a PNG of 3,840 x 2,160 without transparency", () async {
      final image = img.Image(width: 3840, height: 2160);
      final pixels = image.data!.buffer.asUint8List();
      for (var i = 0; i < pixels.length; i += 3) {
        final x = (i ~/ 3) % 3840;
        pixels[i] = x % 256;
        pixels[i + 1] = (x ~/ 15) % 256;
        pixels[i + 2] = 200;
      }
      final png = img.encodePng(image);
      expect(readImageHeader(png)!.width, 3840);
      await expectNotReencoded(png, "screenshot.png");
    });

    test("an animated GIF", () async {
      final first = img.Image(width: 2700, height: 60, numChannels: 3);
      img.fill(first, color: img.ColorRgb8(200, 30, 30));
      final second = img.Image(width: 2700, height: 60, numChannels: 3);
      img.fill(second, color: img.ColorRgb8(30, 30, 200));
      first.addFrame(second);
      final gif = img.encodeGif(first);
      expect(readImageHeader(gif)!.width, 2700);
      await expectNotReencoded(gif, "animation.gif");
    });

    test("an animated WebP", () async {
      await expectNotReencoded(fixture("animated_exif.webp"), "animation.webp");
    });
  });

  test(
      "a photo whose reduced copy would be larger goes as attached: "
      "without its metadata, at its own size", () async {
    // Noise at quality 10: the reduced copy, at 85, is larger.
    final original = withExifOf(
        cornerJpeg(2700, 1800, quality: 10), fixture("gps_exif.jpg"));
    final attachment = await attached(original);
    final withoutMetadata = attachment.data!;
    expect(withoutMetadata.length, lessThan(original.length));

    final (content, uploaded) = await send(attachment);

    final reduced =
        (await attachment.imagePreparation(preparer: preparer))!.reduced!;
    expect(reduced.bytes.length, greaterThanOrEqualTo(withoutMetadata.length),
        reason: "the case under test");
    expect(uploaded, withoutMetadata);
    expect(await readExifFromBytes(uploaded), isEmpty);
    final info = content["info"] as Map<String, dynamic>;
    expect((info["w"], info["h"]), (2700, 1800));
  });

  test("\"Send original\" (reduce off): the exact bytes, at full size",
      () async {
    final original =
        withExifOf(cornerJpeg(2700, 1800), fixture("gps_exif.jpg"));
    final attachment = PendingFileAttachment(
        name: "photo.jpg",
        data: Uint8List.fromList(original),
        size: original.length,
        mimeType: "image/jpeg");
    expect(attachment.reducePhoto, isFalse);

    final (content, uploaded) = await send(attachment);

    expect(uploaded, original);
    expect(engine.decodes, [(800, null)]);
    final info = content["info"] as Map<String, dynamic>;
    expect((info["w"], info["h"]), (2700, 1800));
  });
}
