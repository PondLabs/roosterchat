import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A 2000 x 1500 JPEG with a solid colour in each corner and noise
/// between (so it is well over 300 kB), with [fixture]'s Exif block (its
/// orientation) spliced in after SOI.
Uint8List largeJpegWithExifOf(Uint8List fixture) {
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
Uint8List noisyPng(int width, int height, {required bool transparent}) {
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
