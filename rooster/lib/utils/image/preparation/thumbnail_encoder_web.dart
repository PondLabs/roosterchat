import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:rooster/utils/image/metadata/image_container.dart';
import 'package:rooster/utils/image/preparation/blurhash_rgba.dart';
import 'package:rooster/utils/image/preparation/thumbnail_encoder.dart';
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

ThumbnailEncoder platformThumbnailEncoder() => const CanvasThumbnailEncoder();

/// Encodes through the browser: the pixels go into an `OffscreenCanvas`
/// and `convertToBlob` encodes them off the UI thread. `compute` would run
/// the `image` package's encoder on the UI thread here, since the web has
/// no isolates. The blurhash comes from a small copy the canvas scales. A
/// reduced photo is encoded the same way, and the thumbnail is scaled from
/// it.
class CanvasThumbnailEncoder implements ThumbnailEncoder {
  const CanvasThumbnailEncoder();

  @override
  Future<ThumbnailResult> encode(ThumbnailRequest request) async {
    final maxSide = request.maxSide;
    final reduceTo = request.reduceTo;
    // Decoded at the blurhash's size already: nothing for a canvas to do.
    if (maxSide == null &&
        reduceTo == null &&
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

    ReducedPhoto? reduced;
    if (reduceTo != null) {
      canvas = _fit(canvas, reduceTo);
      // The browser writes no metadata either, but the photo goes through
      // the same allowlist as an attached file all the same.
      final bytes = parseImageContainer(
              await _encode(canvas, "image/jpeg", photoJpegQuality))
          ?.withoutMetadata();
      if (bytes != null) {
        reduced = ReducedPhoto(
            bytes: bytes, width: canvas.width, height: canvas.height);
      }
    }

    if (maxSide == null) {
      _release(canvas);
      return ThumbnailResult(blurhash: blurhash, reduced: reduced);
    }

    final png = request.mayHaveAlpha && hasTransparency(request.rgba);
    final mimeType = png ? "image/png" : "image/jpeg";
    canvas = _fit(canvas, maxSide);
    final (w, h) = (canvas.width, canvas.height);
    final bytes = await _encode(canvas, mimeType, thumbnailJpegQuality);
    _release(canvas);
    return ThumbnailResult(
      blurhash: blurhash,
      reduced: reduced,
      thumbnail: PreparedThumbnail(
          bytes: bytes, mimeType: mimeType, width: w, height: h),
    );
  }

  /// [canvas] encoded by the browser, off the UI thread.
  static Future<Uint8List> _encode(
      web.OffscreenCanvas canvas, String mimeType, int quality) async {
    final blob = await canvas
        .convertToBlob(
            web.ImageEncodeOptions(type: mimeType, quality: quality / 100))
        .toDart;
    final buffer = await blob.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  /// [canvas] scaled down to at most [maxSide] on its long side (the old
  /// one released), or [canvas] itself when it already fits.
  static web.OffscreenCanvas _fit(web.OffscreenCanvas canvas, int maxSide) {
    final (w, h) = fitWithin(canvas.width, canvas.height, maxSide);
    if (w == canvas.width && h == canvas.height) return canvas;
    final scaled = _scaled(canvas, w, h);
    _release(canvas);
    return scaled;
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
