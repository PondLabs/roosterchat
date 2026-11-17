import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

const fixtures = "unit_test/fixtures/image_metadata";

Uint8List fixture(String name) => File("$fixtures/$name").readAsBytesSync();

/// The folder with the 12 MP photo (`photo12mp.jpg`), or null: tests that
/// need it are skipped without it.
String? get sampleDir => Platform.environment["SPEED_SAMPLE_DIR"];

/// A noisy [width] x [height] JPEG at [quality], with a solid colour in
/// each corner (red, green, blue, yellow from the top left, clockwise but
/// for the last two: bottom left blue, bottom right yellow), so a turn
/// shows.
Uint8List cornerJpeg(int width, int height, {int quality = 90, int seed = 7}) {
  final image = img.Image(width: width, height: height);
  final pixels = image.data!.buffer.asUint8List();
  final random = Random(seed);
  final cw = width ~/ 5, ch = height ~/ 5;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final left = x < cw, right = x >= width - cw;
      final top = y < ch, bottom = y >= height - ch;
      final (r, g, b) = top && left
          ? (255, 0, 0)
          : top && right
              ? (0, 200, 0)
              : bottom && left
                  ? (0, 0, 255)
                  : bottom && right
                      ? (255, 220, 0)
                      : (
                          random.nextInt(256),
                          random.nextInt(256),
                          random.nextInt(256)
                        );
      pixels[i] = r;
      pixels[i + 1] = g;
      pixels[i + 2] = b;
    }
  }
  return img.encodeJpg(image, quality: quality);
}

/// [jpeg] with the first APP1 (Exif) segment of [exifFrom] put right after
/// its SOI: its orientation, or its GPS.
Uint8List withExifOf(Uint8List jpeg, Uint8List exifFrom) {
  var pos = 2;
  while (true) {
    final marker = exifFrom[pos + 1];
    final length = (exifFrom[pos + 2] << 8) | exifFrom[pos + 3];
    if (marker == 0xE1) {
      return Uint8List.fromList([
        ...jpeg.sublist(0, 2),
        ...exifFrom.sublist(pos, pos + 2 + length),
        ...jpeg.sublist(2),
      ]);
    }
    pos += 2 + length;
  }
}

/// The markers of a JPEG's segments before its scan (APPn, DQT, SOF, …).
List<int> jpegMarkersBeforeScan(Uint8List jpeg) {
  final markers = <int>[];
  var pos = 2;
  while (pos + 4 <= jpeg.length) {
    final marker = jpeg[pos + 1];
    markers.add(marker);
    if (marker == 0xDA) break;
    pos += 2 + ((jpeg[pos + 2] << 8) | jpeg[pos + 3]);
  }
  return markers;
}

/// What the engine draws for [bytes]: its size and straight RGBA, decoded
/// at [targetWidth] when given.
Future<(int, int, Uint8List)> engineDecode(Uint8List bytes,
    {int? targetWidth}) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
  final image = (await codec.getNextFrame()).image;
  try {
    final data =
        (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
    return (image.width, image.height, data.buffer.asUint8List());
  } finally {
    image.dispose();
    codec.dispose();
  }
}

/// The colour at ([fx], [fy]) of the picture (fractions of its size).
(int, int, int) colourAt((int, int, Uint8List) decoded, double fx, double fy) {
  final (w, h, rgba) = decoded;
  final i = ((fy * h).floor() * w + (fx * w).floor()) * 4;
  return (rgba[i], rgba[i + 1], rgba[i + 2]);
}

/// Whether two colours are within [tolerance] on every channel (JPEG
/// moves a solid colour a little).
bool near((int, int, int) a, (int, int, int) b, {int tolerance = 40}) =>
    (a.$1 - b.$1).abs() <= tolerance &&
    (a.$2 - b.$2).abs() <= tolerance &&
    (a.$3 - b.$3).abs() <= tolerance;
