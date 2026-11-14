import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/utils/image/metadata/remove_image_metadata.dart';

/// Times the rewrite of a 12 MP phone photo. The photo is not in the
/// repository: point SPEED_SAMPLE_DIR at a folder holding `photo12mp.jpg`.
/// Without it the test is skipped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dir = Platform.environment["SPEED_SAMPLE_DIR"];
  final skip = dir == null
      ? "SPEED_SAMPLE_DIR is not set: no 12 MP photo to time the rewrite on"
      : null;

  test("a 12 MP JPEG is rewritten in under 100 ms", skip: skip, () async {
    final photo = File("$dir/photo12mp.jpg").readAsBytesSync();

    // The same photo with a phone's Exif (GPS, orientation 6) after SOI.
    final exif = File("unit_test/fixtures/image_metadata/orientation_6.jpg")
        .readAsBytesSync();
    expect(String.fromCharCodes(exif, 24, 28), "Exif");
    final exifEnd = 2 + 18 + 2 + ((exif[22] << 8) | exif[23]);
    final withExif = Uint8List.fromList([
      ...photo.sublist(0, 2),
      ...exif.sublist(20, exifEnd),
      ...photo.sublist(2)
    ]);

    for (final (label, bytes) in [
      ("photo12mp.jpg", photo),
      ("photo12mp.jpg with Exif", withExif),
    ]) {
      final watch = Stopwatch()..start();
      final result = removeMetadataByRewrite(bytes);
      watch.stop();
      expect(result!.outcome, MetadataRemovalOutcome.rewritten);
      expect(result.bytes!.length, lessThanOrEqualTo(bytes.length));

      final background = Stopwatch()..start();
      await removeImageMetadata(bytes);
      background.stop();

      // ignore: avoid_print
      print("$label: ${bytes.length} bytes, rewrite "
          "${watch.elapsedMicroseconds / 1000} ms; with the isolate "
          "${background.elapsedMicroseconds / 1000} ms");
      expect(watch.elapsedMilliseconds, lessThan(100), reason: label);
    }
  });
}
