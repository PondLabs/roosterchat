import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/utils/image/metadata/image_container.dart';
import 'package:rooster/utils/image/preparation/blurhash_rgba.dart';
import 'package:rooster/utils/image/preparation/thumbnail_encoder.dart';

ThumbnailEncoder platformThumbnailEncoder() => const IsolateThumbnailEncoder();

/// Encodes in a background isolate with the `image` package: the pixels
/// are already at thumbnail size, or at the reduced photo's, so the copy
/// into the isolate is small.
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
  final reduceTo = request.reduceTo;
  if (maxSide == null && reduceTo == null) {
    return ThumbnailResult(blurhash: blurhash);
  }

  var image = img.Image.fromBytes(
      width: request.width,
      height: request.height,
      bytes: request.rgba.buffer,
      bytesOffset: request.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba);

  ReducedPhoto? reduced;
  if (reduceTo != null) {
    image = _fit(image, reduceTo);
    // The encoder writes no metadata it is not given, but the photo goes
    // through the same allowlist as an attached file all the same.
    final bytes = parseImageContainer(img.encodeJpg(image,
            quality: photoJpegQuality, chroma: img.JpegChroma.yuv420))
        ?.withoutMetadata();
    if (bytes != null) {
      reduced =
          ReducedPhoto(bytes: bytes, width: image.width, height: image.height);
    }
  }
  if (maxSide == null) {
    return ThumbnailResult(blurhash: blurhash, reduced: reduced);
  }

  image = _fit(image, maxSide);
  final png = request.mayHaveAlpha && hasTransparency(request.rgba);
  final bytes = png
      ? img.encodePng(image)
      : img.encodeJpg(image,
          quality: thumbnailJpegQuality, chroma: img.JpegChroma.yuv420);
  return ThumbnailResult(
    blurhash: blurhash,
    reduced: reduced,
    thumbnail: PreparedThumbnail(
        bytes: bytes,
        mimeType: png ? "image/png" : "image/jpeg",
        width: image.width,
        height: image.height),
  );
}

/// [image] scaled down to at most [maxSide] on its long side; itself when
/// it already fits.
img.Image _fit(img.Image image, int maxSide) {
  final (w, h) = fitWithin(image.width, image.height, maxSide);
  if (w == image.width && h == image.height) return image;
  return img.copyResize(image,
      width: w, height: h, interpolation: img.Interpolation.average);
}
