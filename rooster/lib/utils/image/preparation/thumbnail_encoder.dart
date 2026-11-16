import 'dart:typed_data';

import 'package:rooster/utils/image/preparation/thumbnail_encoder_native.dart'
    if (dart.library.js_interop) 'package:rooster/utils/image/preparation/thumbnail_encoder_web.dart'
    as platform;

/// JPEG quality of a thumbnail.
const int thumbnailJpegQuality = 80;

/// The long side of the small copy a blurhash is computed from.
const int blurhashSourceSide = 32;

/// Pixels decoded once by the engine, handed to a [ThumbnailEncoder].
class ThumbnailRequest {
  const ThumbnailRequest({
    required this.rgba,
    required this.width,
    required this.height,
    required this.maxSide,
    required this.mayHaveAlpha,
  });

  /// Straight (not premultiplied) RGBA, [width] by [height].
  final Uint8List rgba;
  final int width;
  final int height;

  /// The thumbnail's long side at most; null when only the blurhash is
  /// wanted.
  final int? maxSide;

  /// False for a format without transparency (JPEG): the pixels are not
  /// scanned for it.
  final bool mayHaveAlpha;
}

/// An encoded thumbnail.
class PreparedThumbnail {
  const PreparedThumbnail({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;

  /// `image/jpeg`, or `image/png` for a picture with transparency.
  final String mimeType;
  final int width;
  final int height;
}

class ThumbnailResult {
  const ThumbnailResult({this.thumbnail, this.blurhash});

  /// Null when none was asked for or the encoder could not make one.
  final PreparedThumbnail? thumbnail;
  final String? blurhash;
}

/// Turns decoded pixels into a thumbnail (JPEG at [thumbnailJpegQuality],
/// PNG when a pixel is not opaque) and a blurhash, away from the UI
/// thread's heavy work: on native in a background isolate, with the
/// `image` package (`encodeJpg`, 4:2:0 chroma); on the web through the
/// browser's canvas encoder.
abstract interface class ThumbnailEncoder {
  Future<ThumbnailResult> encode(ThumbnailRequest request);

  /// The encoder of the platform the app runs on.
  static ThumbnailEncoder platformDefault() =>
      platform.platformThumbnailEncoder();
}

/// Whether any pixel of straight RGBA [rgba] is not fully opaque.
bool hasTransparency(Uint8List rgba) {
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 0xFF) return true;
  }
  return false;
}

/// The size that fits [width] by [height] within [maxSide] on its long
/// side, keeping the aspect ratio; the same size when it already fits.
(int, int) fitWithin(int width, int height, int maxSide) {
  final long = width >= height ? width : height;
  if (long <= maxSide) return (width, height);
  final scale = maxSide / long;
  int side(int v) {
    final scaled = (v * scale).round();
    return scaled < 1 ? 1 : scaled;
  }

  return width >= height ? (maxSide, side(height)) : (side(width), maxSide);
}

/// A box-filtered copy of straight RGBA [rgba] at most [maxSide] on its
/// long side: what a blurhash is computed from.
(Uint8List, int, int) downsampleRgba(
    Uint8List rgba, int width, int height, int maxSide) {
  final (w, h) = fitWithin(width, height, maxSide);
  if (w == width && h == height) return (rgba, width, height);
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final y0 = y * height ~/ h;
    var y1 = (y + 1) * height ~/ h;
    if (y1 <= y0) y1 = y0 + 1;
    for (var x = 0; x < w; x++) {
      final x0 = x * width ~/ w;
      var x1 = (x + 1) * width ~/ w;
      if (x1 <= x0) x1 = x0 + 1;
      var r = 0, g = 0, b = 0, a = 0;
      for (var sy = y0; sy < y1; sy++) {
        var i = (sy * width + x0) * 4;
        for (var sx = x0; sx < x1; sx++) {
          r += rgba[i];
          g += rgba[i + 1];
          b += rgba[i + 2];
          a += rgba[i + 3];
          i += 4;
        }
      }
      final n = (y1 - y0) * (x1 - x0);
      final o = (y * w + x) * 4;
      out[o] = r ~/ n;
      out[o + 1] = g ~/ n;
      out[o + 2] = b ~/ n;
      out[o + 3] = a ~/ n;
    }
  }
  return (out, w, h);
}
