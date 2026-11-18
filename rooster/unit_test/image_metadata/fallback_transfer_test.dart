@TestOn('vm')
library;

import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/utils/image/metadata/image_container.dart';
import 'package:rooster/utils/image/metadata/remove_image_metadata.dart';
import 'package:rooster/utils/image/metadata/rgba_transfer.dart';

import 'fallback_size_cap_test.dart' show enginePixels, fallbackAt, unparsable;

/// How the fallback's pixels reach its background encode.
void main() {
  test(
      "a 4032 x 3024 picture's pixels cross into the isolate as a "
      "TransferableTypedData, and the output is the same as before", () async {
    final picture = img.Image(width: 4032, height: 3024);
    for (final p in picture) {
      p
        ..r = (p.x * 255) ~/ 4031
        ..g = (p.y * 255) ~/ 3023
        ..b = (p.x ^ p.y) & 0xFF;
    }
    final input = unparsable(img.encodeJpg(picture, quality: 85));
    expect(parseImageContainer(input), isNull);

    final sent = <Object>[];
    final result =
        await removeImageMetadata(input, encodeInBackground: (pixels) {
      sent.add(pixels.rgba.payload);
      // The app's own background encode, in a real isolate.
      return compute(encodeFallback, pixels);
    });

    expect(sent.single, isA<TransferableTypedData>());
    expect(result.outcome, MetadataRemovalOutcome.reencoded);
    // Before: the engine's pixels copied by `img.Image.fromBytes`, then
    // encoded at the quality the steps chose.
    final before = fallbackAt(await enginePixels(input), result.jpegQuality!);
    expect(result.bytes, before);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test("the image the encoder reads is the unpacked buffer itself", () {
    final random = Uint8List.fromList(
        List.generate(40 * 30 * 4, (i) => i % 4 == 3 ? 0xFF : i * 31 & 0xFF));
    final rgba = PackedRgba(random).unpack();
    final image = rgbaImage(rgba, 40, 30);

    expect((image.width, image.height, image.numChannels), (40, 30, 4));
    final copied = img.Image.fromBytes(
        width: 40,
        height: 30,
        bytes: random.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba);
    expect(image.getPixel(7, 11), copied.getPixel(7, 11));
    expect(img.encodeJpg(image, quality: 90, chroma: img.JpegChroma.yuv420),
        img.encodeJpg(copied, quality: 90, chroma: img.JpegChroma.yuv420));
    expect(img.encodePng(image), img.encodePng(copied));

    // No copy of the pixels: the image reads the same memory.
    rgba[(11 * 40 + 7) * 4] = 0x5A;
    expect(image.getPixel(7, 11).r, 0x5A);
  });

  test("pixels that do not span their buffer are copied, not misread", () {
    final buffer = Uint8List(4 + 2 * 2 * 4);
    for (var i = 4; i < buffer.length; i++) {
      buffer[i] = i;
    }
    final view = Uint8List.sublistView(buffer, 4);
    final image = rgbaImage(view, 2, 2);
    expect(image.toUint8List(), view);
    view[0] = 0;
    expect(image.getPixel(0, 0).r, 4, reason: "a copy");
  });
}
