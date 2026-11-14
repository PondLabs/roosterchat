import 'dart:typed_data';

import 'package:rooster/utils/image/metadata/exif_orientation.dart';
import 'package:rooster/utils/image/metadata/image_container.dart';

/// A PNG read as its list of chunks, up to IEND.
///
/// Kept by [withoutMetadata]: the signature and IHDR, PLTE, IDAT, IEND,
/// tRNS, gAMA, cHRM, sRGB, iCCP, cICP, sBIT, pHYs and the APNG chunks
/// (acTL, fcTL, fdAT), each copied with its CRC. Every other chunk goes
/// (tEXt, zTXt, iTXt, eXIf, tIME, private chunks), and so does anything
/// after IEND.
class PngContainer implements ImageContainer {
  PngContainer._(this._bytes, this._chunks,
      {required this.orientation, required bool exifPrefixed})
      : _exifPrefixed = exifPrefixed;

  /// Whether the original eXIf had the `Exif\0\0` prefix.
  final bool _exifPrefixed;

  final Uint8List _bytes;

  /// Byte ranges of the chunks to keep, IHDR first.
  final List<(int, int)> _chunks;

  @override
  final int orientation;

  @override
  String get mimeType => "image/png";

  static const _signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  static const _keep = {
    "IHDR", "PLTE", "IDAT", "IEND", "tRNS", "gAMA", "cHRM", "sRGB", //
    "iCCP", "cICP", "sBIT", "pHYs", "acTL", "fcTL", "fdAT",
  };

  static bool matches(Uint8List bytes) {
    if (bytes.length < _signature.length) return false;
    for (var i = 0; i < _signature.length; i++) {
      if (bytes[i] != _signature[i]) return false;
    }
    return true;
  }

  /// Parses [bytes], or returns null when they are not a complete PNG: the
  /// first chunk is not IHDR, a chunk runs past the end, or there is no
  /// IEND.
  static PngContainer? parse(Uint8List bytes) {
    if (!matches(bytes)) return null;
    final data = ByteData.sublistView(bytes);
    final chunks = <(int, int)>[];
    int? orientation;
    var exifPrefixed = false;
    var pos = _signature.length;

    while (true) {
      if (pos + 12 > bytes.length) return null;
      final length = data.getUint32(pos);
      final end = pos + 12 + length;
      if (length > 0x7FFFFFFF || end > bytes.length) return null;
      final type = String.fromCharCodes(bytes, pos + 4, pos + 8);
      if (chunks.isEmpty && type != "IHDR") return null;

      if (_keep.contains(type)) {
        chunks.add((pos, end));
      } else if (type == "eXIf" && orientation == null) {
        final exif = Uint8List.sublistView(bytes, pos + 8, end - 4);
        orientation = readExifOrientation(exif);
        exifPrefixed = hasExifPrefix(exif);
      }
      pos = end;
      if (type == "IEND") break;
    }

    return PngContainer._(bytes, chunks,
        orientation: orientation ?? exifOrientationNormal,
        exifPrefixed: exifPrefixed);
  }

  @override
  Uint8List withoutMetadata() {
    final out = BytesBuilder(copy: false)..add(_signature);
    for (var i = 0; i < _chunks.length; i++) {
      final (start, end) = _chunks[i];
      out.add(Uint8List.sublistView(_bytes, start, end));
      if (i == 0 && orientation != exifOrientationNormal) {
        out.add(_chunk("eXIf",
            minimalOrientationExif(orientation, prefixed: _exifPrefixed)));
      }
    }
    return out.takeBytes();
  }

  static Uint8List _chunk(String type, Uint8List payload) {
    final out = Uint8List(12 + payload.length);
    final data = ByteData.sublistView(out);
    data.setUint32(0, payload.length);
    out.setRange(4, 8, type.codeUnits);
    out.setRange(8, 8 + payload.length, payload);
    data.setUint32(8 + payload.length,
        _crc32(Uint8List.sublistView(out, 4, 8 + payload.length)));
    return out;
  }

  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc32(Uint8List bytes) {
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}
