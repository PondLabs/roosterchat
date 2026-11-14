import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/utils/image/metadata/exif_orientation.dart';
import 'package:rooster/utils/image/metadata/image_container.dart';
import 'package:rooster/utils/image/metadata/remove_image_metadata.dart';

/// The fixtures are made by `unit_test/fixtures/image_metadata/generate.py`;
/// its README says what each one holds.
Uint8List fixture(String name) =>
    File('unit_test/fixtures/image_metadata/$name').readAsBytesSync();

/// Text from the fixtures' metadata. None of it may survive.
const _personalText = [
  "Jane Example",
  "Rooster Test Camera",
  "Model T-1",
  "2026:11:14",
  "Sao Paulo",
  "Brazil",
  "Jane's house",
  "GPSLatitude",
  "MicroVideoOffset",
  "ftypmp42",
  "mdat",
  "private vendor data",
];

/// Markers of metadata blocks that must not survive anywhere in the file.
const _forbiddenText = ["http://ns.adobe.com/xap", "Photoshop 3.0", "MPF"];

/// A fixture that parses, with the orientation it is shown with.
class _Case {
  const _Case(this.file, this.orientation, {this.frames = 1});
  final String file;
  final int orientation;
  final int frames;
}

const _parsedCases = [
  _Case("gps_exif.jpg", 1),
  _Case("gps_xmp.jpg", 1),
  _Case("iptc.jpg", 1),
  _Case("mpf.jpg", 1),
  _Case("motion_photo.jpg", 1),
  _Case("cmyk.jpg", 1),
  _Case("orientation_3.jpg", 3),
  _Case("orientation_6.jpg", 6),
  _Case("orientation_8.jpg", 8),
  _Case("text_exif.png", 6),
  _Case("animated_exif.webp", 6, frames: 3),
  _Case("animated_exif_prefixed.webp", 6, frames: 3),
];

/// Every frame as the engine draws it, as RGBA bytes with its size.
Future<List<(int, int, Uint8List)>> render(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frames = <(int, int, Uint8List)>[];
  for (var i = 0; i < codec.frameCount; i++) {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frames.add((image.width, image.height, rgba!.buffer.asUint8List()));
    image.dispose();
  }
  codec.dispose();
  return frames;
}

bool _contains(Uint8List haystack, String needle) =>
    _indexOf(haystack, needle) >= 0;

/// Walks a JPEG on its own (not with the code under test) and returns the
/// APPn and COM segments as (marker, payload), and where the walk ended.
(List<(int, Uint8List)>, int) walkJpeg(Uint8List b) {
  final segments = <(int, Uint8List)>[];
  expect(b[0] == 0xFF && b[1] == 0xD8, isTrue, reason: "starts with SOI");
  var pos = 2;
  while (true) {
    expect(b[pos], 0xFF, reason: "a marker at $pos");
    final marker = b[pos + 1];
    if (marker == 0xD9) return (segments, pos + 2);
    final length = (b[pos + 2] << 8) | b[pos + 3];
    final payload = Uint8List.sublistView(b, pos + 4, pos + 2 + length);
    if ((marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE) {
      segments.add((marker, payload));
    }
    pos += 2 + length;
    if (marker == 0xDA) {
      while (!(b[pos] == 0xFF &&
          b[pos + 1] != 0x00 &&
          (b[pos + 1] < 0xD0 || b[pos + 1] > 0xD7))) {
        pos++;
      }
    }
  }
}

/// Walks PNG chunks on their own; returns the types and where IEND ended.
(List<String>, int) walkPng(Uint8List b) {
  final types = <String>[];
  var pos = 8;
  while (true) {
    final length = ByteData.sublistView(b).getUint32(pos);
    final type = String.fromCharCodes(b, pos + 4, pos + 8);
    types.add(type);
    pos += 12 + length;
    if (type == "IEND") return (types, pos);
  }
}

/// Walks RIFF chunks on their own; returns the types and the RIFF end.
(List<String>, int) walkWebp(Uint8List b) {
  final data = ByteData.sublistView(b);
  final end = 8 + data.getUint32(4, Endian.little);
  final types = <String>[];
  var pos = 12;
  while (pos < end) {
    types.add(String.fromCharCodes(b, pos, pos + 4));
    final size = data.getUint32(pos + 4, Endian.little);
    pos += 8 + size + (size & 1);
  }
  return (types, end);
}

const _keptJpegApp = {0xE0, 0xE2, 0xEE};
const _keptPng = {
  "IHDR", "PLTE", "IDAT", "IEND", "tRNS", "gAMA", "cHRM", "sRGB", //
  "iCCP", "cICP", "sBIT", "pHYs", "acTL", "fcTL", "fdAT",
};
const _keptWebp = {"VP8 ", "VP8L", "VP8X", "ALPH", "ANIM", "ANMF", "ICCP"};

/// The privacy checks every output has to pass, parsed or re-encoded.
Future<void> expectNoMetadata(Uint8List out, {required int orientation}) async {
  final exif = await readExifFromBytes(out);
  if (orientation == exifOrientationNormal) {
    expect(exif.keys, isEmpty, reason: "the exif package reads nothing");
  } else {
    expect(exif.keys, ["Image Orientation"],
        reason: "the exif package reads the orientation and nothing else");
    expect(exif["Image Orientation"]!.values.firstAsInt(), orientation);
  }
  for (final text in [..._personalText, ..._forbiddenText]) {
    expect(_contains(out, text), isFalse, reason: "'$text' is gone");
  }

  if (out[0] == 0xFF) {
    final (segments, end) = walkJpeg(out);
    expect(end, out.length, reason: "the file ends at the first EOI");
    for (final (marker, payload) in segments) {
      final id = latin1.decode(payload.sublist(0, payload.length.clamp(0, 12)),
          allowInvalid: true);
      if (marker == 0xE1) {
        expect(orientation, isNot(exifOrientationNormal),
            reason: "an Exif segment only to carry an orientation");
        expect(payload.length, 6 + 26, reason: "a minimal Exif");
        continue;
      }
      expect(_keptJpegApp, contains(marker),
          reason: "APP${marker - 0xE0} / COM is not on the list ($id)");
      if (marker == 0xE0) {
        expect(id.startsWith("JFIF\u0000"), isTrue, reason: id);
        expect(payload.length, 14, reason: "JFIF without a thumbnail");
        expect(payload[12] | payload[13], 0, reason: "thumbnail is 0 by 0");
      }
      if (marker == 0xE2) expect(id, "ICC_PROFILE\u0000");
      if (marker == 0xEE) expect(id.startsWith("Adobe"), isTrue);
    }
  } else if (out[0] == 0x89) {
    final (types, end) = walkPng(out);
    expect(end, out.length, reason: "the file ends at IEND");
    for (final type in types) {
      if (type == "eXIf" && orientation != exifOrientationNormal) continue;
      expect(_keptPng, contains(type), reason: "$type is not on the list");
    }
  } else {
    final (types, end) = walkWebp(out);
    expect(end, out.length, reason: "the file ends at the RIFF length");
    for (final type in types) {
      if (type == "EXIF" && orientation != exifOrientationNormal) continue;
      expect(_keptWebp, contains(type), reason: "$type is not on the list");
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("a file that parses is rewritten", () {
    for (final c in _parsedCases) {
      test(c.file, () async {
        final original = fixture(c.file);
        final result = await removeImageMetadata(original);

        expect(result.outcome, MetadataRemovalOutcome.rewritten);
        expect(result.mimeType, parseImageContainer(original)!.mimeType);
        final out = result.bytes!;
        expect(out.length, lessThanOrEqualTo(original.length),
            reason: "never larger than the original");
        expect(out.length, lessThan(original.length),
            reason: "the fixture's metadata took some room");
        expect(parseImageContainer(original)!.orientation, c.orientation);

        await expectNoMetadata(out, orientation: c.orientation);

        final before = await render(original);
        final after = await render(out);
        expect(after.length, c.frames, reason: "same number of frames");
        expect(after.length, before.length);
        for (var i = 0; i < before.length; i++) {
          final (w, h, pixels) = before[i];
          expect(after[i].$1, w, reason: "frame $i width");
          expect(after[i].$2, h, reason: "frame $i height");
          expect(after[i].$3, pixels, reason: "frame $i pixels");
        }
      });
    }
  });

  test("the fixtures carry what they claim", () async {
    for (final c in _parsedCases) {
      final original = fixture(c.file);
      final readable = (await readExifFromBytes(original)).keys.toSet()
        ..remove("Image Orientation");
      final hasText = [..._personalText, ..._forbiddenText]
          .any((t) => _contains(original, t));
      expect(readable.isNotEmpty || hasText, isTrue, reason: c.file);
    }
    expect(_contains(fixture("gps_xmp.jpg"), "GPSLatitude"), isTrue);
    expect(_contains(fixture("iptc.jpg"), "Photoshop 3.0"), isTrue);
    expect(_contains(fixture("mpf.jpg"), "MPF"), isTrue);
    expect(_contains(fixture("motion_photo.jpg"), "ftypmp42"), isTrue);
    expect(_contains(fixture("text_exif.png"), "Jane Example"), isTrue);
  });

  test("the JFIF thumbnail goes and the colour profile stays", () {
    final original = fixture("gps_exif.jpg");
    final (before, _) = walkJpeg(original);
    final jfif = before.firstWhere((s) => s.$1 == 0xE0).$2;
    expect((jfif[12], jfif[13]), (4, 3), reason: "the fixture has one");

    final out = removeMetadataByRewrite(original)!.bytes!;
    final (after, _) = walkJpeg(out);
    expect(after.map((s) => s.$1), [0xE0, 0xE2]);
    // The test engine draws without colour management, so the pixel check
    // cannot see a lost profile: compare the profile itself.
    final icc = before.firstWhere((s) => s.$1 == 0xE2).$2;
    expect(after[1].$2, icc);
  });

  test("a PNG keeps its transparency", () async {
    final out = removeMetadataByRewrite(fixture("text_exif.png"))!.bytes!;
    final (_, _, pixels) = (await render(out)).single;
    final alphas = {for (var i = 3; i < pixels.length; i += 4) pixels[i]};
    expect(alphas.length, greaterThan(10));
    expect(alphas, contains(0));
  });

  group("a file that does not parse", () {
    test("is re-encoded when it still decodes", () async {
      final original = fixture("truncated_decodable.jpg");
      expect(parseImageContainer(original), isNull);
      expect(_contains(original, "Jane Example"), isTrue);

      final result = await removeImageMetadata(original);
      expect(result.outcome, MetadataRemovalOutcome.reencoded);
      expect(result.mimeType, "image/jpeg");
      await expectNoMetadata(result.bytes!, orientation: 1);
      final (w, h, _) = (await render(result.bytes!)).single;
      expect((w, h), (256, 192));
    });

    test("fails when it does not decode either", () async {
      final original = fixture("truncated_undecodable.jpg");
      expect(parseImageContainer(original), isNull);
      final result = await removeImageMetadata(original);
      expect(result.outcome, MetadataRemovalOutcome.failed);
      expect(result.bytes, isNull);
    });

    test("a re-encode keeps the picture upright", () async {
      // The cut progressive JPEG with its Exif swapped for orientation 6:
      // shown 192 by 256, so stored 192 by 256 after the re-encode.
      final cut = fixture("truncated_decodable.jpg");
      final exifLength = (cut[4] << 8) | cut[5];
      final tiff = minimalOrientationTiff(6);
      final rotated = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE1, 0, 2 + 6 + tiff.length, //
        ..."Exif\u0000\u0000".codeUnits, ...tiff,
        ...cut.sublist(4 + exifLength),
      ]);
      expect((await render(rotated)).single.$1, 192);

      final result = await removeImageMetadata(rotated);
      expect(result.outcome, MetadataRemovalOutcome.reencoded);
      await expectNoMetadata(result.bytes!, orientation: 1);
      final decoded = img.decodeJpg(result.bytes!)!;
      expect((decoded.width, decoded.height), (192, 256));
    });

    test("a PNG cut before IEND comes back a PNG with its transparency",
        () async {
      final png = fixture("text_exif.png");
      final cut = png.sublist(0, _indexOf(png, "IEND") - 4);
      final result = await removeImageMetadata(cut);
      expect(result.outcome, MetadataRemovalOutcome.reencoded);
      expect(result.mimeType, "image/png");
      await expectNoMetadata(result.bytes!, orientation: 1);
      final (_, _, pixels) = (await render(result.bytes!)).single;
      expect(pixels[3], 0, reason: "the left edge stays transparent");
    });

    test("an opaque WebP cut short comes back a JPEG", () async {
      final webp = fixture("animated_exif.webp");
      final result =
          await removeImageMetadata(webp.sublist(0, webp.length - 100));
      expect(result.outcome, MetadataRemovalOutcome.reencoded);
      expect(result.mimeType, "image/jpeg");
      await expectNoMetadata(result.bytes!, orientation: 1);
    });
  });

  test("GIF and BMP are left as they are", () {
    final gif = img.encodeGif(img.Image(width: 4, height: 4));
    final bmp = img.encodeBmp(img.Image(width: 4, height: 4));
    for (final bytes in [gif, bmp]) {
      final result = removeMetadataByRewrite(bytes)!;
      expect(result.outcome, MetadataRemovalOutcome.untouched);
      expect(identical(result.bytes, bytes), isTrue);
    }
  });

  group("Exif orientation", () {
    test("the minimal block reads back", () {
      for (var o = 1; o <= 8; o++) {
        expect(readTiffOrientation(minimalOrientationTiff(o)), o);
      }
    });

    test("a malformed block reads as normal", () {
      expect(readTiffOrientation(Uint8List(4)), 1);
      expect(readTiffOrientation(Uint8List.fromList("II*\u0000".codeUnits)), 1);
    });
  });
}

int _indexOf(Uint8List haystack, String needle) {
  final pattern = latin1.encode(needle);
  outer:
  for (var i = 0; i + pattern.length <= haystack.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (haystack[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}
