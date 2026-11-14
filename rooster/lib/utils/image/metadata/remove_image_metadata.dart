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
  /// again without metadata (JPEG at quality 90; PNG for a PNG or for a
  /// picture with transparency).
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
  const MetadataRemoval(this.outcome, {this.bytes, this.mimeType});

  final MetadataRemovalOutcome outcome;

  /// The picture to send, null when [outcome] is
  /// [MetadataRemovalOutcome.failed].
  final Uint8List? bytes;

  /// The MIME type of [bytes]. After a re-encode it can differ from the
  /// input's (a WebP comes out as JPEG or PNG).
  final String? mimeType;
}

/// JPEG quality of the re-encode a picture falls back to.
const int metadataFallbackJpegQuality = 90;

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
/// encoding the pixels again in the background.
Future<MetadataRemoval> removeImageMetadata(Uint8List bytes) async {
  final rewritten = await compute<Uint8List, MetadataRemoval?>(
      removeMetadataByRewrite, bytes);
  if (rewritten != null) return rewritten;

  final decoded = await _decodeWithEngine(bytes);
  if (decoded == null) {
    return const MetadataRemoval(MetadataRemovalOutcome.failed);
  }
  final reencoded =
      await compute<_Pixels, MetadataRemoval?>(_encodeWithoutMetadata, decoded);
  return reencoded ?? const MetadataRemoval(MetadataRemovalOutcome.failed);
}

/// Straight-alpha RGBA pixels of a picture's first frame, as shown.
class _Pixels {
  const _Pixels(this.width, this.height, this.rgba, {required this.asPng});
  final int width;
  final int height;
  final Uint8List rgba;
  final bool asPng;
}

Future<_Pixels?> _decodeWithEngine(Uint8List bytes) async {
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
    return _Pixels(image.width, image.height, rgba, asPng: asPng);
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

MetadataRemoval? _encodeWithoutMetadata(_Pixels pixels) {
  final image = img.Image.fromBytes(
      width: pixels.width,
      height: pixels.height,
      bytes: pixels.rgba.buffer,
      bytesOffset: pixels.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba);
  final encoded = pixels.asPng
      ? img.encodePng(image)
      : img.encodeJpg(image,
          quality: metadataFallbackJpegQuality, chroma: img.JpegChroma.yuv420);

  // The encoder writes no metadata it is not given, but the output goes
  // through the same allowlist as a parsed file all the same.
  final container = parseImageContainer(encoded);
  if (container == null) return null;
  return MetadataRemoval(MetadataRemovalOutcome.reencoded,
      bytes: container.withoutMetadata(), mimeType: container.mimeType);
}

bool _isGif(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x47 && // G
    bytes[1] == 0x49 && // I
    bytes[2] == 0x46 && // F
    bytes[3] == 0x38; // 8

bool _isBmp(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D; // BM
