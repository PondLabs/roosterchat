import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/utils/image/preparation/blurhash_rgba.dart';
import 'package:rooster/utils/image/preparation/thumbnail_encoder.dart';

ThumbnailEncoder platformThumbnailEncoder() => const IsolateThumbnailEncoder();

/// Encodes in a background isolate with the `image` package: the pixels
/// are already at thumbnail size, so the copy into the isolate is small.
class IsolateThumbnailEncoder implements ThumbnailEncoder {
  const IsolateThumbnailEncoder();

  @override
  Future<ThumbnailResult> encode(ThumbnailRequest request) =>
      compute(encodeThumbnailWithImagePackage, request);
}

/// The encode itself, on whatever isolate calls it.
ThumbnailResult encodeThumbnailWithImagePackage(ThumbnailRequest request) {
  final blurhash = blurhashOfRgba(request.rgba, request.width, request.height);
  final maxSide = request.maxSide;
  if (maxSide == null) return ThumbnailResult(blurhash: blurhash);

  var image = img.Image.fromBytes(
      width: request.width,
      height: request.height,
      bytes: request.rgba.buffer,
      bytesOffset: request.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba);
  final (w, h) = fitWithin(request.width, request.height, maxSide);
  if (w != request.width || h != request.height) {
    image = img.copyResize(image,
        width: w, height: h, interpolation: img.Interpolation.average);
  }

  final png = request.mayHaveAlpha && hasTransparency(request.rgba);
  final bytes = png
      ? img.encodePng(image)
      : img.encodeJpg(image,
          quality: thumbnailJpegQuality, chroma: img.JpegChroma.yuv420);
  return ThumbnailResult(
    blurhash: blurhash,
    thumbnail: PreparedThumbnail(
        bytes: bytes,
        mimeType: png ? "image/png" : "image/jpeg",
        width: w,
        height: h),
  );
}
