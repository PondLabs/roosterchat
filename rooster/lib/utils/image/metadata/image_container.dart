import 'dart:typed_data';

import 'package:rooster/utils/image/metadata/jpeg_container.dart';
import 'package:rooster/utils/image/metadata/png_container.dart';
import 'package:rooster/utils/image/metadata/webp_container.dart';

/// A still or animated picture's file, read as its container (JPEG
/// segments, PNG chunks, RIFF chunks) without decoding a pixel.
///
/// Parsing is strict: a file that is cut short, has a length that runs
/// past its end, or uses a structure the reader does not know is not
/// parsed at all, so a caller never sends a half-understood file as if its
/// metadata were gone.
abstract interface class ImageContainer {
  /// The MIME type of the format the container was read as.
  String get mimeType;

  /// The Exif orientation (1 to 8) a decoder would apply, 1 when the file
  /// has none.
  int get orientation;

  /// The same picture without metadata, built by keeping only what a
  /// decoder needs to draw it (an allowlist per format). Image data is
  /// copied byte for byte, never decoded or encoded again. An orientation
  /// other than 1 is written back as an Exif block holding only that tag.
  Uint8List withoutMetadata();
}

/// Reads [bytes] as a JPEG, PNG or WebP container. Returns null for any
/// other format and for a file of one of these formats that does not parse
/// cleanly.
ImageContainer? parseImageContainer(Uint8List bytes) {
  if (JpegContainer.matches(bytes)) return JpegContainer.parse(bytes);
  if (PngContainer.matches(bytes)) return PngContainer.parse(bytes);
  if (WebpContainer.matches(bytes)) return WebpContainer.parse(bytes);
  return null;
}
