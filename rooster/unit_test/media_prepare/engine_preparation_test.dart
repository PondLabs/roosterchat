import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/image/image_header.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import 'fakes.dart';

/// The preparation with the real engine and the native encoder: sizes as
/// displayed, the thumbnail's format, size and orientation.
///
/// The 12 MP photo is not in the repository: point SPEED_SAMPLE_DIR at a
/// folder holding `photo12mp.jpg`, or its test is skipped. With
/// T22_EVIDENCE_DIR set, the photo's thumbnail is written there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fixtures = "unit_test/fixtures/image_metadata";

  ImagePreparer preparer() => ImagePreparer(log: SpeedLog(frames: NoFrames()));

  for (final orientation in [6, 8]) {
    test("orientation $orientation fixture: width and height as displayed",
        () async {
      final bytes =
          File("$fixtures/orientation_$orientation.jpg").readAsBytesSync();
      final header = readImageHeader(bytes)!;
      expect((header.storedWidth, header.storedHeight), (64, 48));
      expect(header.orientation, orientation);

      final prepared = await preparer().prepare(bytes);
      expect((prepared!.width, prepared.height), (48, 64),
          reason: "swapped against the SOF");
      final drawn = await _decode(bytes);
      expect((prepared.width, prepared.height), (drawn.width, drawn.height),
          reason: "as the engine draws it");
      expect(prepared.thumbnail, isNull, reason: "a 1.9 kB source");
    });

    test(
        "orientation $orientation, large: the thumbnail is the picture "
        "as displayed", () async {
      final bytes = _largeWithExifOf(
          File("$fixtures/orientation_$orientation.jpg").readAsBytesSync());
      expect(bytes.length, greaterThanOrEqualTo(thumbnailMinSourceBytes));

      final prepared = await preparer().prepare(bytes);
      expect((prepared!.width, prepared.height), (1500, 2000),
          reason: "stored 2000 x 1500");
      final thumbnail = prepared.thumbnail!;
      expect(thumbnail.mimeType, "image/jpeg");
      expect((thumbnail.width, thumbnail.height), (600, 800));

      // Each corner of the thumbnail has the colour of the same corner of
      // the engine's own drawing of the original.
      final shown = await _decode(bytes, targetWidth: thumbnail.width);
      final thumb = await _decode(thumbnail.bytes);
      expect((thumb.width, thumb.height), (600, 800));
      expect((shown.width, shown.height), (600, 800));
      for (final corner in _Corner.values) {
        final want = await _cornerColour(shown, corner);
        final got = await _cornerColour(thumb, corner);
        expect(_distance(want, got), lessThan(24),
            reason: "$corner: want $want, got $got");
      }
      shown.dispose();
      thumb.dispose();
    });
  }

  test("orientation 3 turns the picture half round: no swap", () async {
    final bytes = File("$fixtures/orientation_3.jpg").readAsBytesSync();
    final prepared = await preparer().prepare(bytes);
    expect((prepared!.width, prepared.height), (64, 48));
  });

  test("the prefixed-Exif WebP: as the engine draws it", () async {
    for (final name in ["animated_exif.webp", "animated_exif_prefixed.webp"]) {
      final bytes = File("$fixtures/$name").readAsBytesSync();
      final prepared = await preparer().prepare(bytes);
      final drawn = await _decode(bytes);
      expect((prepared!.width, prepared.height), (drawn.width, drawn.height),
          reason: name);
      expect(prepared.animated, isTrue, reason: name);
      drawn.dispose();
    }
  });

  test("a PNG with transparency gets a PNG thumbnail, an opaque one a JPEG",
      () async {
    for (final (transparent, mime) in [
      (true, "image/png"),
      (false, "image/jpeg"),
    ]) {
      final bytes = _noisyPng(1600, 1200, transparent: transparent);
      expect(bytes.length, greaterThanOrEqualTo(thumbnailMinSourceBytes));
      final prepared = await preparer().prepare(bytes);
      final thumbnail = prepared!.thumbnail!;
      expect(thumbnail.mimeType, mime);
      expect((thumbnail.width, thumbnail.height), (800, 600));
      expect(readImageHeader(thumbnail.bytes)!.mimeType, mime);
      if (transparent) {
        final decoded = img.decodePng(thumbnail.bytes)!;
        expect(decoded.numChannels, 4);
        expect(decoded.getPixel(10, 10).a, 0, reason: "the clear corner");
        expect(decoded.getPixel(700, 500).a, 255);
      }
    }
  });

  final dir = Platform.environment["SPEED_SAMPLE_DIR"];
  test("the 12 MP photo's thumbnail: JPEG, at most 250 kB, 800 px long",
      skip: dir == null
          ? "SPEED_SAMPLE_DIR is not set: no 12 MP photo to prepare"
          : null, () async {
    final bytes = File("$dir/photo12mp.jpg").readAsBytesSync();
    final header = readImageHeader(bytes)!;
    final watch = Stopwatch()..start();
    final prepared = await preparer().prepare(bytes);
    watch.stop();
    final thumbnail = prepared!.thumbnail!;
    // ignore: avoid_print
    print("photo12mp.jpg: ${bytes.length} bytes, ${header.width} x "
        "${header.height}; prepared in ${watch.elapsedMilliseconds} ms: "
        "${prepared.width} x ${prepared.height}, thumbnail "
        "${thumbnail.mimeType} ${thumbnail.width} x ${thumbnail.height}, "
        "${thumbnail.bytes.length} bytes, blurhash ${prepared.blurhash}");
    expect(thumbnail.mimeType, "image/jpeg");
    expect(thumbnail.bytes.length, lessThanOrEqualTo(250 * 1000));
    expect(max(thumbnail.width, thumbnail.height), 800);
    expect((prepared.width, prepared.height), (header.width, header.height));
    expect(prepared.blurhash, isNotNull);
    final evidence = Platform.environment["T22_EVIDENCE_DIR"];
    if (evidence != null) {
      File("$evidence/photo12mp-thumbnail.jpg")
          .writeAsBytesSync(thumbnail.bytes);
    }
  });
}

Future<ui.Image> _decode(Uint8List bytes, {int? targetWidth}) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  return image;
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

/// The mean colour of a block a tenth of the picture in from [corner].
Future<(int, int, int)> _cornerColour(ui.Image image, _Corner corner) async {
  final data =
      (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  final w = image.width, h = image.height;
  final bw = w ~/ 10, bh = h ~/ 10;
  final x0 = switch (corner) {
    _Corner.topLeft || _Corner.bottomLeft => bw ~/ 2,
    _ => w - bw - bw ~/ 2,
  };
  final y0 = switch (corner) {
    _Corner.topLeft || _Corner.topRight => bh ~/ 2,
    _ => h - bh - bh ~/ 2,
  };
  var r = 0, g = 0, b = 0;
  for (var y = y0; y < y0 + bh; y++) {
    for (var x = x0; x < x0 + bw; x++) {
      final i = (y * w + x) * 4;
      r += data.getUint8(i);
      g += data.getUint8(i + 1);
      b += data.getUint8(i + 2);
    }
  }
  final n = bw * bh;
  return (r ~/ n, g ~/ n, b ~/ n);
}

int _distance((int, int, int) a, (int, int, int) b) =>
    (a.$1 - b.$1).abs() + (a.$2 - b.$2).abs() + (a.$3 - b.$3).abs();

/// A 2000 x 1500 JPEG with a solid colour in each corner and noise
/// between (so it is well over 300 kB), with [fixture]'s Exif block (its
/// orientation) spliced in after SOI.
Uint8List _largeWithExifOf(Uint8List fixture) {
  final image = img.Image(width: 2000, height: 1500);
  final random = Random(7);
  const corners = [
    (255, 0, 0), // top left: red
    (0, 200, 0), // top right: green
    (0, 0, 255), // bottom left: blue
    (255, 220, 0), // bottom right: yellow
  ];
  for (var y = 0; y < 1500; y++) {
    for (var x = 0; x < 2000; x++) {
      final left = x < 400,
          right = x >= 1600,
          top = y < 300,
          bottom = y >= 1200;
      final (r, g, b) = top && left
          ? corners[0]
          : top && right
              ? corners[1]
              : bottom && left
                  ? corners[2]
                  : bottom && right
                      ? corners[3]
                      : (
                          random.nextInt(256),
                          random.nextInt(256),
                          random.nextInt(256)
                        );
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  final jpeg = img.encodeJpg(image, quality: 90);
  // The fixture's APP1: the first segment after SOI and APP0.
  var pos = 2;
  late int start, end;
  while (true) {
    final marker = fixture[pos + 1];
    final length = (fixture[pos + 2] << 8) | fixture[pos + 3];
    if (marker == 0xE1) {
      start = pos;
      end = pos + 2 + length;
      break;
    }
    pos += 2 + length;
  }
  return Uint8List.fromList([
    ...jpeg.sublist(0, 2),
    ...fixture.sublist(start, end),
    ...jpeg.sublist(2)
  ]);
}

/// A noisy RGBA PNG; with [transparent], its top-left quarter is clear.
Uint8List _noisyPng(int width, int height, {required bool transparent}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  final random = Random(3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final clear = transparent && x < width ~/ 4 && y < height ~/ 4;
      image.setPixelRgba(x, y, random.nextInt(256), random.nextInt(256),
          random.nextInt(256), clear ? 0 : 255);
    }
  }
  return img.encodePng(image);
}
