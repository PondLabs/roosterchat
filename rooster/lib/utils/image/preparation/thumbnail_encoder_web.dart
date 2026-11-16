import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:rooster/utils/image/preparation/blurhash_rgba.dart';
import 'package:rooster/utils/image/preparation/thumbnail_encoder.dart';
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

ThumbnailEncoder platformThumbnailEncoder() => const CanvasThumbnailEncoder();

/// Encodes through the browser: the pixels go into an `OffscreenCanvas`
/// and `convertToBlob` encodes them off the UI thread. `compute` would run
/// the `image` package's encoder on the UI thread here, since the web has
/// no isolates. The blurhash comes from a small copy the canvas scales.
class CanvasThumbnailEncoder implements ThumbnailEncoder {
  const CanvasThumbnailEncoder();

  @override
  Future<ThumbnailResult> encode(ThumbnailRequest request) async {
    final maxSide = request.maxSide;
    // Decoded at the blurhash's size already: nothing for a canvas to do.
    if (maxSide == null &&
        max(request.width, request.height) <= blurhashSourceSide) {
      return ThumbnailResult(
          blurhash:
              blurhashOfRgba(request.rgba, request.width, request.height));
    }

    var canvas = web.OffscreenCanvas(request.width, request.height);
    final context = _context(canvas);
    final pixels = Uint8ClampedList.sublistView(request.rgba);
    context.putImageData(
        web.ImageData(pixels.toJS, request.width, request.height.toJS), 0, 0);

    // The blurhash's small copy, scaled by the browser: the same loop in
    // Dart takes about 90 ms of the UI thread in a debug build.
    final (bw, bh) =
        fitWithin(request.width, request.height, blurhashSourceSide);
    final small = _scaled(canvas, bw, bh);
    final smallPixels = _context(small).getImageData(0, 0, bw, bh).data.toDart;
    final blurhash = blurhashOfRgba(Uint8List.sublistView(smallPixels), bw, bh);
    _release(small);

    if (maxSide == null) {
      _release(canvas);
      return ThumbnailResult(blurhash: blurhash);
    }

    final png = request.mayHaveAlpha && hasTransparency(request.rgba);
    final mimeType = png ? "image/png" : "image/jpeg";
    final (w, h) = fitWithin(request.width, request.height, maxSide);
    if (w != request.width || h != request.height) {
      final scaled = _scaled(canvas, w, h);
      _release(canvas);
      canvas = scaled;
    }

    final blob = await canvas
        .convertToBlob(web.ImageEncodeOptions(
            type: mimeType, quality: thumbnailJpegQuality / 100))
        .toDart;
    final buffer = await blob.arrayBuffer().toDart;
    _release(canvas);
    return ThumbnailResult(
      blurhash: blurhash,
      thumbnail: PreparedThumbnail(
          bytes: buffer.toDart.asUint8List(),
          mimeType: mimeType,
          width: w,
          height: h),
    );
  }

  static web.OffscreenCanvasRenderingContext2D _context(
          web.OffscreenCanvas canvas) =>
      canvas.getContext("2d") as web.OffscreenCanvasRenderingContext2D;

  /// [source] drawn into a new canvas of [width] by [height].
  static web.OffscreenCanvas _scaled(
      web.OffscreenCanvas source, int width, int height) {
    final scaled = web.OffscreenCanvas(width, height);
    final context = _context(scaled);
    context.imageSmoothingQuality = "high";
    context.drawImage(source, 0, 0, width, height);
    return scaled;
  }

  /// Lets the browser take a canvas's memory back now, not at collection.
  static void _release(web.OffscreenCanvas canvas) {
    canvas.width = 0;
    canvas.height = 0;
  }
}
