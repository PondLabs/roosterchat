import 'dart:typed_data';

import 'package:rooster/utils/image/metadata/exif_orientation.dart';
import 'package:rooster/utils/image/metadata/image_container.dart';

/// A WebP read as its RIFF chunks, up to the length the RIFF header gives.
///
/// Kept by [withoutMetadata]: VP8, VP8L, VP8X (its EXIF and XMP flags
/// corrected), ALPH, ANIM, ANMF and ICCP, so an animation stays one. Every
/// other chunk goes (EXIF, XMP, unknown chunks), and so does anything after
/// the RIFF length.
class WebpContainer implements ImageContainer {
  WebpContainer._(this._bytes, this._chunks,
      {required this.orientation, required bool exifPrefixed})
      : _exifPrefixed = exifPrefixed;

  /// Whether the original EXIF had the `Exif\0\0` prefix.
  final bool _exifPrefixed;

  final Uint8List _bytes;

  /// Byte ranges of the chunks to keep, padding included.
  final List<(int, int)> _chunks;

  @override
  final int orientation;

  @override
  String get mimeType => "image/webp";

  static const _keep = {
    "VP8 ", "VP8L", "VP8X", "ALPH", "ANIM", "ANMF", "ICCP", //
  };

  static const _flagExif = 0x08;
  static const _flagXmp = 0x04;

  static bool matches(Uint8List bytes) =>
      bytes.length >= 12 &&
      String.fromCharCodes(bytes, 0, 4) == "RIFF" &&
      String.fromCharCodes(bytes, 8, 12) == "WEBP";

  /// Parses [bytes], or returns null when they are not a complete WebP: the
  /// RIFF length runs past the end, a chunk runs past the RIFF length, or
  /// the first chunk is not VP8, VP8L or VP8X.
  static WebpContainer? parse(Uint8List bytes) {
    if (!matches(bytes)) return null;
    final data = ByteData.sublistView(bytes);
    final riffEnd = 8 + data.getUint32(4, Endian.little);
    if (riffEnd > bytes.length || riffEnd < 12) return null;

    final chunks = <(int, int)>[];
    int? orientation;
    var exifPrefixed = false;
    var extended = false;
    var pos = 12;
    while (pos < riffEnd) {
      if (pos + 8 > riffEnd) return null;
      final type = String.fromCharCodes(bytes, pos, pos + 4);
      final size = data.getUint32(pos + 4, Endian.little);
      final end = pos + 8 + size + (size & 1);
      // The last chunk's padding byte is sometimes left out.
      if (pos + 8 + size > riffEnd) return null;
      if (chunks.isEmpty) {
        if (type == "VP8X") {
          if (size < 10) return null;
          extended = true;
        } else if (type != "VP8 " && type != "VP8L") {
          return null;
        }
      }

      if (_keep.contains(type)) {
        chunks.add((pos, end > riffEnd ? riffEnd : end));
      } else if (type == "EXIF" && extended && orientation == null) {
        final exif = Uint8List.sublistView(bytes, pos + 8, pos + 8 + size);
        orientation = readExifOrientation(exif);
        exifPrefixed = hasExifPrefix(exif);
      }
      pos = end;
    }
    if (chunks.isEmpty) return null;

    return WebpContainer._(bytes, chunks,
        orientation: orientation ?? exifOrientationNormal,
        exifPrefixed: exifPrefixed);
  }

  @override
  Uint8List withoutMetadata() {
    final exif = orientation == exifOrientationNormal
        ? null
        : minimalOrientationExif(orientation, prefixed: _exifPrefixed);
    final out = BytesBuilder(copy: false)
      ..add(const [0x52, 0x49, 0x46, 0x46]) // RIFF
      ..add(const [0, 0, 0, 0]) // length, set below
      ..add(const [0x57, 0x45, 0x42, 0x50]); // WEBP

    for (var i = 0; i < _chunks.length; i++) {
      final (start, end) = _chunks[i];
      final chunk = Uint8List.sublistView(_bytes, start, end);
      if (String.fromCharCodes(chunk, 0, 4) == "VP8X") {
        final fixed = Uint8List.fromList(chunk);
        var flags = fixed[8] & ~(_flagExif | _flagXmp);
        if (exif != null) flags |= _flagExif;
        fixed[8] = flags;
        out.add(fixed);
      } else {
        out.add(chunk);
        // Pad a last chunk that came without its padding byte only when
        // another chunk follows, so the file never grows.
        if (chunk.length.isOdd && (i < _chunks.length - 1 || exif != null)) {
          out.addByte(0);
        }
      }
    }
    // EXIF comes after the image data in an extended file.
    if (exif != null) {
      final header = ByteData(8)
        ..setUint8(0, 0x45) // E
        ..setUint8(1, 0x58) // X
        ..setUint8(2, 0x49) // I
        ..setUint8(3, 0x46) // F
        ..setUint32(4, exif.length, Endian.little);
      out.add(header.buffer.asUint8List());
      out.add(exif);
    }

    final result = out.takeBytes();
    ByteData.sublistView(result).setUint32(4, result.length - 8, Endian.little);
    return result;
  }
}
