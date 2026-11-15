import 'dart:js_interop';
import 'dart:typed_data';

import 'package:rooster/utils/image/preparation/blurhash_rgba.dart';
import 'package:rooster/utils/image/preparation/thumbnail_encoder.dart';
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

ThumbnailEncoder platformThumbnailEncoder() => const CanvasThumbnailEncoder();

/// Encodes through the browser: the pixels go into an `OffscreenCanvas`
/// and `convertToBlob` encodes them off the UI thread. `compute` would run
/// the `image` package's encoder on the UI thread here, since the web has
/// no isolates. The blurhash comes from a 64 px copy, cheap on any thread.
class CanvasThumbnailEncoder implements ThumbnailEncoder {
  const CanvasThumbnailEncoder();

  @override
  Future<ThumbnailResult> encode(ThumbnailRequest request) async {
    final blurhash =
        blurhashOfRgba(request.rgba, request.width, request.height);
    final maxSide = request.maxSide;
    if (maxSide == null) return ThumbnailResult(blurhash: blurhash);

    final png = request.mayHaveAlpha && hasTransparency(request.rgba);
    final mimeType = png ? "image/png" : "image/jpeg";

    var canvas = web.OffscreenCanvas(request.width, request.height);
    final context =
        canvas.getContext("2d") as web.OffscreenCanvasRenderingContext2D;
    final pixels = Uint8ClampedList.sublistView(request.rgba);
    context.putImageData(
        web.ImageData(pixels.toJS, request.width, request.height.toJS), 0, 0);

    final (w, h) = fitWithin(request.width, request.height, maxSide);
    if (w != request.width || h != request.height) {
      final scaled = web.OffscreenCanvas(w, h);
      final scaledContext =
          scaled.getContext("2d") as web.OffscreenCanvasRenderingContext2D;
      scaledContext.imageSmoothingQuality = "high";
      scaledContext.drawImage(canvas, 0, 0, w, h);
      canvas.width = 0; // let the browser take the memory back now
      canvas.height = 0;
      canvas = scaled;
    }

    final blob = await canvas
        .convertToBlob(web.ImageEncodeOptions(
            type: mimeType, quality: thumbnailJpegQuality / 100))
        .toDart;
    final buffer = await blob.arrayBuffer().toDart;
    canvas.width = 0;
    canvas.height = 0;
    return ThumbnailResult(
      blurhash: blurhash,
      thumbnail: PreparedThumbnail(
          bytes: buffer.toDart.asUint8List(),
          mimeType: mimeType,
          width: w,
          height: h),
    );
  }
}
