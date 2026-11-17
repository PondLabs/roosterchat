import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart' show NoFrames;
import 'photos.dart';

/// The segments of [jpeg] before its scan, by marker: each one's payload
/// (after its length), in order.
List<(int, Uint8List)> _segments(Uint8List jpeg) {
  final segments = <(int, Uint8List)>[];
  var pos = 2;
  while (pos + 4 <= jpeg.length) {
    final marker = jpeg[pos + 1];
    final length = (jpeg[pos + 2] << 8) | jpeg[pos + 3];
    segments.add((marker, jpeg.sublist(pos + 4, pos + 2 + length)));
    if (marker == 0xDA) break;
    pos += 2 + length;
  }
  return segments;
}

/// The sampling factors of each component in [jpeg]'s SOF0 (0x22: two by
/// two, 0x11: one by one).
List<int> _sampling(Uint8List jpeg) {
  final sof = _segments(jpeg).firstWhere((s) => s.$1 == 0xC0).$2;
  final components = sof[5];
  return [for (var i = 0; i < components; i++) sof[6 + i * 3 + 1]];
}

/// [jpeg]'s quantization tables, as written.
List<int> _tables(Uint8List jpeg) => [
      for (final (marker, payload) in _segments(jpeg))
        if (marker == 0xDB) ...payload
    ];

/// The reduced photo is a baseline JPEG at quality 85 with 4:2:0 chroma,
/// whatever the photo it comes from: checked on the app's engine and
/// encoder, without the 12 MP sample.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("a reduced photo is encoded at quality 85, with 4:2:0 chroma", () async {
    // A camera's photo: the repository's GPS Exif on a 2700 x 1800 JPEG
    // encoded at 95 with full chroma, so neither is inherited.
    final original = withExifOf(
        img.encodeJpg(img.decodeJpg(cornerJpeg(2700, 1800))!,
            quality: 95, chroma: img.JpegChroma.yuv444),
        fixture("gps_exif.jpg"));
    expect(_sampling(original), [0x11, 0x11, 0x11]);

    final prepared = await ImagePreparer(log: SpeedLog(frames: NoFrames()))
        .prepare(original, reduce: true);
    final reduced = prepared!.reduced!.bytes;

    expect(_sampling(reduced), [0x22, 0x11, 0x11],
        reason: "luma two by two, each chroma once: 4:2:0");
    // The tables depend on the quality only, not on the pixels.
    Uint8List at(int quality) => img.encodeJpg(img.Image(width: 16, height: 16),
        quality: quality, chroma: img.JpegChroma.yuv420);
    expect(_tables(reduced), _tables(at(photoJpegQuality)));
    expect(photoJpegQuality, 85);
    expect(_tables(at(85)), isNot(_tables(at(90))),
        reason: "the comparison above tells qualities apart");
  });
}
