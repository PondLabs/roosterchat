import 'dart:typed_data';

import 'package:rooster/utils/image/metadata/exif_orientation.dart';
import 'package:rooster/utils/image/metadata/image_container.dart';

/// A JPEG read as its list of segments, up to the first EOI.
///
/// Kept by [withoutMetadata]: SOI; APP0 `JFIF` with its embedded thumbnail
/// removed (written back as 0 by 0); APP2 `ICC_PROFILE`; APP14 `Adobe`
/// (it says how a CMYK picture's colours are stored); the quantization,
/// Huffman, arithmetic coding, restart interval, frame and scan segments
/// with their entropy-coded data; EOI. Every other APPn and COM segment
/// goes (Exif, XMP, IPTC, MPF, vendor data), and so does everything after
/// the first EOI: a phone's motion photo keeps a video with sound there,
/// and MPF a second picture.
class JpegContainer implements ImageContainer {
  JpegContainer._(this._bytes, this._parts, this._insertExifAt,
      {required this.orientation});

  final Uint8List _bytes;

  /// Ranges of [_bytes] to keep, in order, or a replacement for one.
  final List<_Part> _parts;

  /// Index in [_parts] where a minimal Exif goes: after SOI and APP0.
  final int _insertExifAt;

  @override
  final int orientation;

  @override
  String get mimeType => "image/jpeg";

  static bool matches(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;

  /// Parses [bytes], or returns null when they are not a complete JPEG:
  /// a segment that runs past the end, a scan with no marker after it, no
  /// EOI, or a marker outside the allowlist that is not APPn or COM.
  static JpegContainer? parse(Uint8List bytes) {
    if (!matches(bytes)) return null;
    final parts = <_Part>[_Part(0, 2)];
    var insertExifAt = 1;
    int? orientation;
    var sawFrame = false;
    var pos = 2;
    final length = bytes.length;

    while (true) {
      if (pos >= length || bytes[pos] != 0xFF) return null;
      // Any number of 0xFF fill bytes may come before a marker.
      while (pos < length && bytes[pos] == 0xFF) {
        pos++;
      }
      if (pos >= length) return null;
      final marker = bytes[pos];
      final markerStart = pos - 1;
      pos++;

      if (marker == 0xD9) {
        // EOI: the picture ends here, whatever follows.
        if (!sawFrame) return null;
        parts.add(_Part(markerStart, pos));
        break;
      }
      if (_isStandalone(marker)) {
        parts.add(_Part(markerStart, pos));
        continue;
      }
      if (marker == 0x00 || marker == 0xD8) return null;

      if (pos + 2 > length) return null;
      final segmentLength = (bytes[pos] << 8) | bytes[pos + 1];
      if (segmentLength < 2) return null;
      final end = pos + segmentLength;
      if (end > length) return null;
      final payloadStart = pos + 2;

      if (marker == 0xE0) {
        // APP0: JFIF stays without its thumbnail; JFXX and others go.
        if (_startsWith(bytes, payloadStart, end, _jfif) &&
            end - payloadStart >= 14) {
          parts.add(_Part.replaced(_jfifWithoutThumbnail(bytes, payloadStart)));
          if (insertExifAt == 1) insertExifAt = parts.length;
        }
      } else if (marker == 0xE1) {
        // APP1: Exif and XMP go; the first Exif's orientation is kept.
        if (orientation == null &&
            _startsWith(bytes, payloadStart, end, _exif)) {
          orientation = readTiffOrientation(
              Uint8List.sublistView(bytes, payloadStart + _exif.length, end));
        }
      } else if (marker == 0xE2) {
        if (_startsWith(bytes, payloadStart, end, _iccProfile)) {
          parts.add(_Part(markerStart, end));
        }
      } else if (marker == 0xEE) {
        if (_startsWith(bytes, payloadStart, end, _adobe)) {
          parts.add(_Part(markerStart, end));
        }
      } else if ((marker >= 0xE3 && marker <= 0xEF) || marker == 0xFE) {
        // Every other APPn and COM: dropped.
      } else if (_isFrame(marker)) {
        sawFrame = true;
        parts.add(_Part(markerStart, end));
      } else if (marker == 0xDA) {
        // SOS, then its entropy-coded data up to the next real marker.
        if (!sawFrame) return null;
        final dataEnd = _endOfEntropyCodedData(bytes, end);
        if (dataEnd < 0) return null;
        parts.add(_Part(markerStart, dataEnd));
        pos = dataEnd;
        continue;
      } else if (_isTable(marker)) {
        parts.add(_Part(markerStart, end));
      } else {
        return null;
      }
      pos = end;
    }

    return JpegContainer._(bytes, parts, insertExifAt,
        orientation: orientation ?? exifOrientationNormal);
  }

  @override
  Uint8List withoutMetadata() {
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < _parts.length; i++) {
      if (i == _insertExifAt && orientation != exifOrientationNormal) {
        out.add(_exifSegment(orientation));
      }
      final part = _parts[i];
      out.add(part.replacement ??
          Uint8List.sublistView(_bytes, part.start, part.end));
    }
    return out.takeBytes();
  }

  /// RSTn and TEM carry no length.
  static bool _isStandalone(int marker) =>
      (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01;

  /// SOF0 to SOF15, except DHT (C4), JPG (C8) and DAC (CC).
  static bool _isFrame(int marker) =>
      marker >= 0xC0 &&
      marker <= 0xCF &&
      marker != 0xC4 &&
      marker != 0xC8 &&
      marker != 0xCC;

  /// DHT, DAC, DQT, DNL, DRI, DHP, EXP.
  static bool _isTable(int marker) =>
      marker == 0xC4 ||
      marker == 0xCC ||
      (marker >= 0xDB && marker <= 0xDF && marker != 0xDA);

  /// Returns where the marker after a scan starts, or -1 when the file ends
  /// first. Inside a scan, 0xFF is followed by 0x00 (a stuffed byte), by a
  /// restart marker, or by more 0xFF fill bytes before a marker.
  static int _endOfEntropyCodedData(Uint8List bytes, int start) {
    final last = bytes.length - 1;
    var i = start;
    while (i < last) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final next = bytes[i + 1];
      if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
        i += 2;
      } else if (next == 0xFF) {
        i++;
      } else {
        return i;
      }
    }
    return -1;
  }

  static Uint8List _jfifWithoutThumbnail(Uint8List bytes, int payloadStart) {
    // FFE0, length 16, "JFIF\0", version (2), units (1), densities (4),
    // thumbnail width and height written as 0.
    final out = Uint8List(18);
    out[0] = 0xFF;
    out[1] = 0xE0;
    out[2] = 0;
    out[3] = 16;
    out.setRange(4, 16, bytes, payloadStart);
    out[16] = 0;
    out[17] = 0;
    return out;
  }

  static Uint8List _exifSegment(int orientation) {
    final tiff = minimalOrientationTiff(orientation);
    final length = 2 + _exif.length + tiff.length;
    return Uint8List.fromList(
        [0xFF, 0xE1, length >> 8, length & 0xFF, ..._exif, ...tiff]);
  }

  static bool _startsWith(
      Uint8List bytes, int start, int end, List<int> prefix) {
    if (end - start < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[start + i] != prefix[i]) return false;
    }
    return true;
  }

  static const _jfif = [0x4A, 0x46, 0x49, 0x46, 0x00]; // JFIF\0
  static const _exif = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // Exif\0\0
  static const _adobe = [0x41, 0x64, 0x6F, 0x62, 0x65]; // Adobe
  static const _iccProfile = [
    // ICC_PROFILE\0
    0x49, 0x43, 0x43, 0x5F, 0x50, 0x52, 0x4F, 0x46, 0x49, 0x4C, 0x45, 0x00,
  ];
}

class _Part {
  _Part(this.start, this.end) : replacement = null;
  _Part.replaced(Uint8List this.replacement)
      : start = 0,
        end = 0;

  final int start;
  final int end;
  final Uint8List? replacement;
}
