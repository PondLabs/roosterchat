import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/utils/image/metadata/image_container.dart';
import 'package:rooster/utils/image/metadata/png_container.dart';

/// How a picture's metadata was dealt with.
enum MetadataRemovalOutcome {
  /// The container was rewritten: same image data, metadata gone.
  rewritten,

  /// The container did not parse, so the picture was decoded and encoded
  /// again without metadata: PNG for a PNG or for a picture with
  /// transparency, otherwise JPEG at the first of
  /// [metadataFallbackJpegQualities] that is no larger than the original
  /// (the last one when none is).
  reencoded,

  /// A format with nothing to remove (GIF, BMP): the bytes are unchanged.
  untouched,

  /// Neither parsed nor decoded: the metadata could not be removed, and
  /// [MetadataRemoval.bytes] is null.
  failed,
}

/// The result of removing a picture's metadata. Plain data, so it crosses
/// isolates.
class MetadataRemoval {
  const MetadataRemoval(this.outcome,
      {this.bytes,
      this.mimeType,
      this.animationLost = false,
      this.jpegQuality});

  final MetadataRemovalOutcome outcome;

  /// The picture to send, null when [outcome] is
  /// [MetadataRemovalOutcome.failed].
  final Uint8List? bytes;

  /// The MIME type of [bytes]. After a re-encode it can differ from the
  /// input's (a WebP comes out as JPEG or PNG).
  final String? mimeType;

  /// The picture was animated and [bytes] hold only its first frame: a
  /// re-encode keeps one frame.
  final bool animationLost;

  /// The JPEG quality [bytes] were encoded at, when the picture was
  /// re-encoded as a JPEG; null otherwise.
  final int? jpegQuality;
}

/// JPEG qualities the re-encode tries in order, stopping at the first whose
/// output is no larger than the original file. When none is, the output at
/// the last one is sent all the same: never the original, which still holds
/// its metadata.
const List<int> metadataFallbackJpegQualities = [90, 80, 70];

/// Picks the JPEG a re-encode sends: [encode] is called with each of
/// [metadataFallbackJpegQualities] in turn until its output is at most
/// [originalLength] bytes, and the last output is kept when none fits.
/// Returns the quality used and its output, or null when [encode] returns
/// null. Pure; [encode] does the work, so a test can count the encodings.
(int, Uint8List)? pickFallbackJpeg(
    int originalLength, Uint8List? Function(int quality) encode) {
  (int, Uint8List)? picked;
  for (final quality in metadataFallbackJpegQualities) {
    final bytes = encode(quality);
    if (bytes == null) return null;
    picked = (quality, bytes);
    if (bytes.length <= originalLength) break;
  }
  return picked;
}

/// Removes metadata without decoding: GIF and BMP come back untouched, a
/// JPEG, PNG or WebP that parses comes back rewritten (see
/// [ImageContainer.withoutMetadata]), and anything else gives null. Pure
/// and synchronous, so it can run in `compute`.
MetadataRemoval? removeMetadataByRewrite(Uint8List bytes) {
  if (_isGif(bytes)) {
    return MetadataRemoval(MetadataRemovalOutcome.untouched,
        bytes: bytes, mimeType: "image/gif");
  }
  if (_isBmp(bytes)) {
    return MetadataRemoval(MetadataRemovalOutcome.untouched,
        bytes: bytes, mimeType: "image/bmp");
  }
  final container = parseImageContainer(bytes);
  if (container == null) return null;
  return MetadataRemoval(MetadataRemovalOutcome.rewritten,
      bytes: container.withoutMetadata(), mimeType: container.mimeType);
}

/// Removes a picture's metadata for the attach dialog: by container rewrite
/// in the background when the file parses, and otherwise by letting the
/// engine decode it (as it would be shown, orientation applied) and
/// encoding the pixels again in the background with [encodeFallback].
///
/// [encodeInBackground] replaces that background encode in tests (to
/// count the encodings, or to see what crosses into the isolate).
Future<MetadataRemoval> removeImageMetadata(Uint8List bytes,
    {Future<MetadataRemoval?> Function(FallbackPixels pixels)?
        encodeInBackground}) async {
  final rewritten = await compute<Uint8List, MetadataRemoval?>(
      removeMetadataByRewrite, bytes);
  if (rewritten != null) return rewritten;

  final decoded = await _decodeWithEngine(bytes);
  if (decoded == null) {
    return const MetadataRemoval(MetadataRemovalOutcome.failed);
  }
  final reencoded = await (encodeInBackground ?? _encodeInBackground)(decoded);
  return reencoded ?? const MetadataRemoval(MetadataRemovalOutcome.failed);
}

Future<MetadataRemoval?> _encodeInBackground(FallbackPixels pixels) =>
    compute<FallbackPixels, MetadataRemoval?>(encodeFallback, pixels);

/// Straight-alpha RGBA pixels of a picture's first frame, as shown, how
/// many frames the picture has, and the size of the file they came from:
/// what the fallback's background encode is given.
class FallbackPixels {
  const FallbackPixels(this.width, this.height, this.rgba,
      {required this.asPng,
      required this.frames,
      required this.originalLength});
  final int width;
  final int height;
  final Uint8List rgba;
  final bool asPng;
  final int frames;
  final int originalLength;
}

/// Encodes [image] as a JPEG at [quality].
typedef FallbackJpegEncoder = Uint8List Function(img.Image image, int quality);

Uint8List _encodeJpeg(img.Image image, int quality) =>
    img.encodeJpg(image, quality: quality, chroma: img.JpegChroma.yuv420);

Future<FallbackPixels?> _decodeWithEngine(Uint8List bytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    image = (await codec.getNextFrame()).image;
    final data =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) return null;
    final rgba =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    // A PNG stays a PNG; anything else becomes a JPEG unless it has
    // transparency to keep, never a PNG for a photo.
    var asPng = PngContainer.matches(bytes);
    for (var i = 3; !asPng && i < rgba.length; i += 4) {
      if (rgba[i] != 0xFF) asPng = true;
    }
    return FallbackPixels(image.width, image.height, rgba,
        asPng: asPng, frames: codec.frameCount, originalLength: bytes.length);
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// The fallback's encode, on whatever isolate calls it: the pixels as a
/// PNG, or as a JPEG at the first of [metadataFallbackJpegQualities] that
/// fits (see [pickFallbackJpeg]), each step encoded only when the one
/// before did not fit. [encodeJpeg] is `img.encodeJpg` with 4:2:0 chroma;
/// a test passes its own to count the encodings.
MetadataRemoval? encodeFallback(FallbackPixels pixels,
    {FallbackJpegEncoder encodeJpeg = _encodeJpeg}) {
  final image = img.Image.fromBytes(
      width: pixels.width,
      height: pixels.height,
      bytes: pixels.rgba.buffer,
      bytesOffset: pixels.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba);
  // The encoder writes no metadata it is not given, but the output goes
  // through the same allowlist as a parsed file all the same.
  Uint8List? clean(Uint8List encoded) =>
      parseImageContainer(encoded)?.withoutMetadata();

  // A PNG has no quality to step down: it is encoded once, whatever its
  // size. A JPEG is encoded from the same pixels at each step it needs.
  if (pixels.asPng) {
    final bytes = clean(img.encodePng(image));
    if (bytes == null) return null;
    return MetadataRemoval(MetadataRemovalOutcome.reencoded,
        bytes: bytes, mimeType: "image/png", animationLost: pixels.frames > 1);
  }
  final picked = pickFallbackJpeg(
      pixels.originalLength, (quality) => clean(encodeJpeg(image, quality)));
  if (picked == null) return null;
  final (quality, bytes) = picked;
  return MetadataRemoval(MetadataRemovalOutcome.reencoded,
      bytes: bytes,
      mimeType: "image/jpeg",
      animationLost: pixels.frames > 1,
      jpegQuality: quality);
}

bool _isGif(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x47 && // G
    bytes[1] == 0x49 && // I
    bytes[2] == 0x46 && // F
    bytes[3] == 0x38; // 8

bool _isBmp(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D; // BM
