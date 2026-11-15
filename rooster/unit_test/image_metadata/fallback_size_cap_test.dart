import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/utils/image/metadata/exif_orientation.dart';
import 'package:rooster/utils/image/metadata/image_container.dart';
import 'package:rooster/utils/image/metadata/remove_image_metadata.dart';

import 'remove_image_metadata_test.dart' show expectNoMetadata, fixture;

/// The picture as the engine hands it to the fallback: straight RGBA.
Future<img.Image> enginePixels(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final data =
      (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
  final out = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: data.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba);
  image.dispose();
  codec.dispose();
  return out;
}

/// What the fallback would send at [quality], measured here on its own.
Uint8List fallbackAt(img.Image pixels, int quality) => removeMetadataByRewrite(
        img.encodeJpg(pixels, quality: quality, chroma: img.JpegChroma.yuv420))!
    .bytes!;

/// [jpeg] behind an Exif whose IFD is cut short: the container does not
/// parse, the engine still decodes all of it, so it takes the fallback.
Uint8List unparsable(Uint8List jpeg) {
  final tiff = Uint8List.sublistView(minimalOrientationTiff(1), 0, 22);
  return Uint8List.fromList([
    0xFF, 0xD8, 0xFF, 0xE1, 0, 2 + 6 + tiff.length, //
    ..."Exif\u0000\u0000".codeUnits, ...tiff,
    ...jpeg.sublist(2),
  ]);
}

/// JPEG pictures of noise and of smooth gradients at many qualities and
/// chroma samplings, as files that take the fallback. Which of them fits
/// at which step depends on the `image` package's encoder, so the tests
/// measure rather than assume.
Iterable<Uint8List> candidates() sync* {
  for (final smooth in [false, true]) {
    final random = Random(7);
    final picture = img.Image(width: 64, height: 48);
    for (final p in picture) {
      if (smooth) {
        p.setRgb(p.x * 4, p.y * 5, (p.x + p.y) * 2 + random.nextInt(30));
      } else {
        p.setRgb(random.nextInt(256), random.nextInt(256), random.nextInt(256));
      }
    }
    for (final chroma in img.JpegChroma.values) {
      for (var quality = 30; quality <= 100; quality += 5) {
        yield unparsable(
            img.encodeJpg(picture, quality: quality, chroma: chroma));
      }
    }
  }
}

/// The first candidate whose fallback is larger than the file at every
/// quality before [fits] and no larger at [fits], with that output.
Future<(Uint8List, Uint8List)> fittingFirstAt(int fits) async {
  for (final input in candidates()) {
    expect(parseImageContainer(input), isNull);
    final pixels = await enginePixels(input);
    var ok = true;
    for (final quality in metadataFallbackJpegQualities) {
      final size = fallbackAt(pixels, quality).length;
      if (quality == fits) {
        ok = size <= input.length;
        break;
      }
      if (size <= input.length) {
        ok = false;
        break;
      }
    }
    if (ok) return (input, fallbackAt(pixels, fits));
  }
  fail("no candidate fits first at quality $fits");
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("pickFallbackJpeg", () {
    (int, int, String) pick(int originalLength, Map<int, int> sizes) {
      final calls = <int>[];
      final (quality, bytes) = pickFallbackJpeg(originalLength, (quality) {
        calls.add(quality);
        return Uint8List(sizes[quality]!);
      })!;
      return (quality, bytes.length, calls.join(","));
    }

    const sizes = {90: 130, 80: 110, 70: 105};

    test("encodes once when quality 90 fits", () {
      expect(pick(130, sizes), (90, 130, "90"));
    });

    test("steps down to 80 when 90 is larger than the original", () {
      expect(pick(110, sizes), (80, 110, "90,80"));
    });

    test("steps down to 70 when 80 is larger too", () {
      expect(pick(105, sizes), (70, 105, "90,80,70"));
    });

    test("keeps quality 70 when nothing fits", () {
      expect(pick(100, sizes), (70, 105, "90,80,70"));
    });

    test("gives null when an encode fails", () {
      expect(pickFallbackJpeg(100, (_) => null), isNull);
    });
  });

  group("the fallback's size", () {
    for (final fits in metadataFallbackJpegQualities) {
      test("is the output at quality $fits when that is the first to fit",
          () async {
        final (input, expected) = await fittingFirstAt(fits);

        final result = await removeImageMetadata(input);
        expect(result.outcome, MetadataRemovalOutcome.reencoded);
        expect(result.mimeType, "image/jpeg");
        expect(result.jpegQuality, fits);
        expect(result.bytes, expected);
        expect(result.bytes!.length, lessThanOrEqualTo(input.length));
        expect(result.bytes, isNot(input));
        await expectNoMetadata(result.bytes!, orientation: 1);
      });
    }

    test("is the output at quality 70 when even that is larger", () async {
      // The truncated JPEG with Exif: 70% of a progressive file, so its
      // re-encode is larger than it at every quality.
      final input = fixture("truncated_decodable.jpg");
      final pixels = await enginePixels(input);
      for (final quality in metadataFallbackJpegQualities) {
        expect(fallbackAt(pixels, quality).length, greaterThan(input.length),
            reason: "quality $quality does not fit");
      }

      final result = await removeImageMetadata(input);
      expect(result.outcome, MetadataRemovalOutcome.reencoded);
      expect(result.mimeType, "image/jpeg");
      expect(result.jpegQuality, 70);
      expect(result.bytes, fallbackAt(pixels, 70));
      expect(result.bytes, isNot(input));
      await expectNoMetadata(result.bytes!, orientation: 1);
    });

    test("of a PNG with transparency is encoded once, whatever its size",
        () async {
      final png = fixture("text_exif.png");
      final iend = String.fromCharCodes(png).indexOf("IEND");
      final cut = png.sublist(0, iend - 4);
      expect(parseImageContainer(cut), isNull);
      final pixels = await enginePixels(cut);
      final expected = removeMetadataByRewrite(img.encodePng(pixels))!.bytes!;

      final result = await removeImageMetadata(cut);
      expect(result.outcome, MetadataRemovalOutcome.reencoded);
      expect(result.mimeType, "image/png");
      expect(result.jpegQuality, isNull);
      expect(result.bytes, expected);
      expect(result.bytes!.length, greaterThan(cut.length),
          reason: "larger than the file, and sent all the same");
      await expectNoMetadata(result.bytes!, orientation: 1);
    });
  });
}
