import 'dart:typed_data';

import 'package:rooster/utils/image/metadata/exif_orientation.dart';

/// A picture's size and orientation, read from its file header without
/// decoding a pixel: JPEG SOF, PNG IHDR, WebP VP8, VP8L or VP8X, GIF's
/// logical screen, BMP's info header. Pure Dart, so it works the same on
/// the web, where `ui.ImageDescriptor` throws for these formats.
class ImageHeader {
  const ImageHeader({
    required this.mimeType,
    required this.storedWidth,
    required this.storedHeight,
    this.orientation = exifOrientationNormal,
  });

  final String mimeType;

  /// The size the pixels are stored at.
  final int storedWidth;
  final int storedHeight;

  /// The Exif orientation (1 to 8) Flutter's engine applies when it draws
  /// the picture: the first Exif block of a JPEG, PNG's `eXIf`, the `EXIF`
  /// chunk of an extended WebP when it is raw TIFF (with an `Exif\0\0`
  /// prefix the engine's WebP decoder skips it, so it counts as 1).
  final int orientation;

  /// Orientations 5 to 8 turn the picture a quarter: a phone's portrait
  /// photo is stored landscape with orientation 6.
  bool get swapsSides => orientation >= 5 && orientation <= 8;

  /// The size the picture is shown at.
  int get width => swapsSides ? storedHeight : storedWidth;
  int get height => swapsSides ? storedWidth : storedHeight;

  @override
  String toString() =>
      "ImageHeader($mimeType, ${storedWidth}x$storedHeight, $orientation)";
}

/// Reads the header of a JPEG, PNG, WebP, GIF or BMP. Returns null for any
/// other format, a header cut short, or a size of zero.
///
/// Every read is checked against the length first: a release web build
/// drops the bounds checks a [RangeError] would come from.
ImageHeader? readImageHeader(Uint8List bytes) {
  final header =
      _jpeg(bytes) ?? _png(bytes) ?? _webp(bytes) ?? _gif(bytes) ?? _bmp(bytes);
  if (header == null) return null;
  if (header.storedWidth <= 0 || header.storedHeight <= 0) return null;
  return header;
}

bool _startsWith(Uint8List bytes, int at, List<int> prefix) {
  if (at + prefix.length > bytes.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[at + i] != prefix[i]) return false;
  }
  return true;
}

int _u16be(Uint8List b, int at) => (b[at] << 8) | b[at + 1];
int _u32be(Uint8List b, int at) =>
    ((b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]) &
    0xFFFFFFFF;
int _u16le(Uint8List b, int at) => b[at] | (b[at + 1] << 8);
int _u24le(Uint8List b, int at) => b[at] | (b[at + 1] << 8) | (b[at + 2] << 16);
int _u32le(Uint8List b, int at) =>
    (b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)) &
    0xFFFFFFFF;
int _s32le(Uint8List b, int at) {
  final v = _u32le(b, at);
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

const _exifPrefix = [0x45, 0x78, 0x69, 0x66, 0, 0]; // Exif\0\0

/// Walks the segments up to the first frame header (SOF0 to SOF15, not
/// DHT, JPG or DAC), taking the orientation from the first Exif APP1 on
/// the way, as `JpegContainer` does.
ImageHeader? _jpeg(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8 || b[2] != 0xFF) {
    return null;
  }
  int? orientation;
  var pos = 2;
  while (true) {
    if (pos >= b.length || b[pos] != 0xFF) return null;
    while (pos < b.length && b[pos] == 0xFF) {
      pos++; // fill bytes
    }
    if (pos >= b.length) return null;
    final marker = b[pos++];
    // Standalone markers: TEM and RSTn have no length.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
    if (marker == 0xD9 || marker == 0xDA || marker == 0x00) return null;
    if (pos + 2 > b.length) return null;
    final length = _u16be(b, pos);
    if (length < 2) return null;
    final end = pos + length;
    if (end > b.length) return null;
    final payload = pos + 2;
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      if (length < 8) return null;
      return ImageHeader(
        mimeType: "image/jpeg",
        storedHeight: _u16be(b, payload + 1),
        storedWidth: _u16be(b, payload + 3),
        orientation: orientation ?? exifOrientationNormal,
      );
    }
    if (marker == 0xE1 &&
        orientation == null &&
        _startsWith(b, payload, _exifPrefix) &&
        payload + _exifPrefix.length <= end) {
      orientation = readTiffOrientation(
              Uint8List.sublistView(b, payload + _exifPrefix.length, end)) ??
          exifOrientationNormal;
    }
    pos = end;
  }
}

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// IHDR, then the chunks up to the first IDAT for an `eXIf` (a decoder
/// reads it before the image data, as the PNG spec requires).
ImageHeader? _png(Uint8List b) {
  if (!_startsWith(b, 0, _pngSignature)) return null;
  if (!_startsWith(b, 12, "IHDR".codeUnits) || b.length < 24) return null;
  final width = _u32be(b, 16);
  final height = _u32be(b, 20);
  var orientation = exifOrientationNormal;
  var pos = 8;
  while (pos + 8 <= b.length) {
    final length = _u32be(b, pos);
    final type = String.fromCharCodes(b, pos + 4, pos + 8);
    final data = pos + 8;
    if (type == "IDAT" || type == "IEND") break;
    if (data + length > b.length) break;
    if (type == "eXIf") {
      orientation =
          readExifOrientation(Uint8List.sublistView(b, data, data + length)) ??
              exifOrientationNormal;
      break;
    }
    pos = data + length + 4; // and the CRC
  }
  return ImageHeader(
      mimeType: "image/png",
      storedWidth: width,
      storedHeight: height,
      orientation: orientation);
}

ImageHeader? _webp(Uint8List b) {
  if (!_startsWith(b, 0, "RIFF".codeUnits) ||
      !_startsWith(b, 8, "WEBP".codeUnits)) {
    return null;
  }
  if (b.length < 20) return null;
  final type = String.fromCharCodes(b, 12, 16);
  const data = 20;
  switch (type) {
    case "VP8 ":
      // Frame tag (3 bytes), start code 9D 01 2A, then 14-bit sizes.
      if (b.length < data + 10) return null;
      if (!_startsWith(b, data + 3, const [0x9D, 0x01, 0x2A])) return null;
      return ImageHeader(
          mimeType: "image/webp",
          storedWidth: _u16le(b, data + 6) & 0x3FFF,
          storedHeight: _u16le(b, data + 8) & 0x3FFF);
    case "VP8L":
      if (b.length < data + 5 || b[data] != 0x2F) return null;
      final bits = _u32le(b, data + 1);
      return ImageHeader(
          mimeType: "image/webp",
          storedWidth: (bits & 0x3FFF) + 1,
          storedHeight: ((bits >> 14) & 0x3FFF) + 1);
    case "VP8X":
      if (b.length < data + 10) return null;
      final width = _u24le(b, data + 4) + 1;
      final height = _u24le(b, data + 7) + 1;
      return ImageHeader(
          mimeType: "image/webp",
          storedWidth: width,
          storedHeight: height,
          orientation: _webpOrientation(b));
    default:
      return null;
  }
}

/// The first `EXIF` chunk of an extended WebP, when it is raw TIFF.
int _webpOrientation(Uint8List b) {
  var pos = 12;
  while (pos + 8 <= b.length) {
    final type = String.fromCharCodes(b, pos, pos + 4);
    final length = _u32le(b, pos + 4);
    final data = pos + 8;
    if (data + length > b.length) break;
    if (type == "EXIF") {
      final exif = Uint8List.sublistView(b, data, data + length);
      if (hasExifPrefix(exif)) return exifOrientationNormal;
      return readTiffOrientation(exif) ?? exifOrientationNormal;
    }
    pos = data + length + (length & 1);
  }
  return exifOrientationNormal;
}

ImageHeader? _gif(Uint8List b) {
  if (!_startsWith(b, 0, "GIF87a".codeUnits) &&
      !_startsWith(b, 0, "GIF89a".codeUnits)) {
    return null;
  }
  if (b.length < 10) return null;
  return ImageHeader(
      mimeType: "image/gif",
      storedWidth: _u16le(b, 6),
      storedHeight: _u16le(b, 8));
}

/// BITMAPCOREHEADER (12 bytes, 16-bit sizes) or a later info header
/// (32-bit signed sizes; a negative height is a top-down bitmap).
ImageHeader? _bmp(Uint8List b) {
  if (!_startsWith(b, 0, "BM".codeUnits) || b.length < 18) return null;
  final headerSize = _u32le(b, 14);
  if (headerSize == 12) {
    if (b.length < 22) return null;
    return ImageHeader(
        mimeType: "image/bmp",
        storedWidth: _u16le(b, 18),
        storedHeight: _u16le(b, 20));
  }
  if (headerSize < 40 || b.length < 26) return null;
  return ImageHeader(
      mimeType: "image/bmp",
      storedWidth: _s32le(b, 18).abs(),
      storedHeight: _s32le(b, 22).abs());
}
