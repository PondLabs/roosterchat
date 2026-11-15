import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/utils/image/image_header.dart';

/// The header reader's table: every format the attach flow sends as an
/// image, built here byte by byte (no fixture file), so the same test runs
/// on the VM and in Chrome.
void main() {
  final cases = <(String, Uint8List, String, int, int, int)>[
    // label, bytes, mime, stored width, stored height, orientation
    ("JPEG baseline", _jpeg(4032, 3024), "image/jpeg", 4032, 3024, 1),
    ("JPEG progressive", _jpeg(640, 480, sof: 0xC2), "image/jpeg", 640, 480, 1),
    (
      "JPEG with Exif orientation 6",
      _jpeg(4032, 3024, exifOrientation: 6),
      "image/jpeg",
      4032,
      3024,
      6
    ),
    (
      "JPEG with Exif orientation 8, fill bytes and a comment",
      _jpeg(300, 200, exifOrientation: 8, comment: true, fill: true),
      "image/jpeg",
      300,
      200,
      8
    ),
    ("PNG", _png(1920, 1080), "image/png", 1920, 1080, 1),
    (
      "PNG with eXIf orientation 6",
      _png(64, 32, exifOrientation: 6),
      "image/png",
      64,
      32,
      6
    ),
    ("WebP VP8 (lossy)", _webpVp8(1023, 767), "image/webp", 1023, 767, 1),
    ("WebP VP8L (lossless)", _webpVp8l(16383, 2), "image/webp", 16383, 2, 1),
    (
      "WebP VP8X (extended)",
      _webpVp8x(5000, 4000),
      "image/webp",
      5000,
      4000,
      1
    ),
    (
      "WebP VP8X with EXIF orientation 6",
      _webpVp8x(800, 600, exif: _tiff(6)),
      "image/webp",
      800,
      600,
      6
    ),
    (
      "WebP VP8X with Exif\\0\\0-prefixed EXIF, which the engine skips",
      _webpVp8x(800, 600,
          exif: Uint8List.fromList([..."Exif".codeUnits, 0, 0, ..._tiff(6)])),
      "image/webp",
      800,
      600,
      1
    ),
    ("GIF", _gif(500, 281), "image/gif", 500, 281, 1),
    ("BMP", _bmp(1280, 720), "image/bmp", 1280, 720, 1),
    ("BMP stored top-down", _bmp(1280, -720), "image/bmp", 1280, 720, 1),
    ("BMP with a core header", _bmpCore(320, 240), "image/bmp", 320, 240, 1),
  ];

  for (final (label, bytes, mime, width, height, orientation) in cases) {
    test("reads $label", () {
      final header = readImageHeader(bytes);
      expect(header, isNotNull, reason: label);
      expect(header!.mimeType, mime);
      expect(header.storedWidth, width);
      expect(header.storedHeight, height);
      expect(header.orientation, orientation);
      final swaps = orientation >= 5;
      expect(header.width, swaps ? height : width);
      expect(header.height, swaps ? width : height);
    });
  }

  test("does not read what is not a known picture or is cut short", () {
    expect(readImageHeader(Uint8List(0)), isNull);
    expect(
        readImageHeader(Uint8List.fromList("hello world".codeUnits)), isNull);
    for (final bytes in [
      _jpeg(4032, 3024),
      _png(1920, 1080),
      _webpVp8(1023, 767),
      _webpVp8l(100, 100),
      _webpVp8x(5000, 4000),
      _gif(500, 281),
      _bmp(1280, 720),
    ]) {
      // The header without its dimensions.
      expect(readImageHeader(Uint8List.sublistView(bytes, 0, 8)), isNull);
    }
    // A JPEG cut inside its frame header.
    final jpeg = _jpeg(10, 10);
    var sof = 2;
    while (!(jpeg[sof] == 0xFF && jpeg[sof + 1] == 0xC0)) {
      sof++;
    }
    expect(readImageHeader(Uint8List.sublistView(jpeg, 0, sof + 6)), isNull);
    // A WebP whose first chunk is not a picture.
    final webp = _webpVp8(10, 10);
    webp.setAll(12, "JUNK".codeUnits);
    expect(readImageHeader(webp), isNull);
  });

  test("a zero width or height is not a picture", () {
    expect(readImageHeader(_png(0, 10)), isNull);
    expect(readImageHeader(_gif(10, 0)), isNull);
    expect(readImageHeader(_jpeg(0, 10)), isNull);
  });
}

// --- Builders -------------------------------------------------------------

Uint8List _u16be(int v) => Uint8List.fromList([(v >> 8) & 0xFF, v & 0xFF]);
Uint8List _u32be(int v) => Uint8List.fromList(
    [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
Uint8List _u16le(int v) => Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]);
Uint8List _u24le(int v) =>
    Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF]);
Uint8List _u32le(int v) => Uint8List.fromList(
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

/// A big-endian TIFF block with one Orientation entry.
Uint8List _tiff(int orientation) => Uint8List.fromList([
      0x4D, 0x4D, 0, 42, 0, 0, 0, 8, // header, IFD0 at 8
      0, 1, // one entry
      0x01, 0x12, 0, 3, 0, 0, 0, 1, ..._u16be(orientation), 0, 0,
      0, 0, 0, 0, // no next IFD
    ]);

Uint8List _segment(int marker, List<int> payload) => Uint8List.fromList(
    [0xFF, marker, ..._u16be(payload.length + 2), ...payload]);

Uint8List _jpeg(int width, int height,
    {int sof = 0xC0,
    int? exifOrientation,
    bool comment = false,
    bool fill = false}) {
  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    ..._segment(0xE0, [..."JFIF".codeUnits, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]),
    if (exifOrientation != null)
      ..._segment(0xE1, [..."Exif".codeUnits, 0, 0, ..._tiff(exifOrientation)]),
    if (comment) ..._segment(0xFE, "made up".codeUnits),
    ..._segment(0xDB, List.filled(65, 1)), // DQT
    ..._segment(0xC4, List.filled(20, 0)), // DHT, not a frame
    if (fill) 0xFF, // fill bytes before a marker
    ..._segment(sof, [
      8, ..._u16be(height), ..._u16be(width), 3, //
      1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1,
    ]),
    ..._segment(0xDA, [3, 1, 0, 2, 0x11, 3, 0x11, 0, 63, 0]),
    0x12, 0x34, 0xFF, 0x00, 0x56, // entropy-coded data
    0xFF, 0xD9, // EOI
  ]);
}

Uint8List _chunk(String type, List<int> data) => Uint8List.fromList(
    [..._u32be(data.length), ...type.codeUnits, ...data, 0, 0, 0, 0]);

Uint8List _png(int width, int height, {int? exifOrientation}) =>
    Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      ..._chunk("IHDR", [..._u32be(width), ..._u32be(height), 8, 6, 0, 0, 0]),
      if (exifOrientation != null) ..._chunk("eXIf", _tiff(exifOrientation)),
      ..._chunk("IDAT", [0x78, 0x9C, 3, 0, 0, 0, 0, 1]),
      ..._chunk("IEND", []),
    ]);

Uint8List _riffChunk(String type, List<int> data) => Uint8List.fromList([
      ...type.codeUnits,
      ..._u32le(data.length),
      ...data,
      if (data.length.isOdd) 0,
    ]);

Uint8List _riff(List<int> chunks) => Uint8List.fromList([
      ..."RIFF".codeUnits,
      ..._u32le(chunks.length + 4),
      ..."WEBP".codeUnits,
      ...chunks,
    ]);

Uint8List _webpVp8(int width, int height) => _riff(_riffChunk("VP8 ", [
      0x50, 0x01, 0x00, // frame tag, key frame
      0x9D, 0x01, 0x2A, // start code
      ..._u16le(width & 0x3FFF), ..._u16le(height & 0x3FFF),
      0, 0, 0, 0,
    ]));

Uint8List _webpVp8l(int width, int height) {
  final bits = (width - 1) | ((height - 1) << 14);
  return _riff(_riffChunk("VP8L", [0x2F, ..._u32le(bits), 0, 0, 0]));
}

Uint8List _webpVp8x(int width, int height, {Uint8List? exif}) => _riff([
      ..._riffChunk("VP8X", [
        exif != null ? 0x08 : 0x00, 0, 0, 0, //
        ..._u24le(width - 1), ..._u24le(height - 1),
      ]),
      ..._riffChunk("VP8L", [0x2F, ..._u32le((width - 1) & 0x3FFF), 0, 0, 0]),
      if (exif != null) ..._riffChunk("EXIF", exif),
    ]);

Uint8List _gif(int width, int height) => Uint8List.fromList([
      ..."GIF89a".codeUnits,
      ..._u16le(width), ..._u16le(height),
      0, 0, 0, // no colour table
      0x3B,
    ]);

Uint8List _bmp(int width, int height) => Uint8List.fromList([
      ..."BM".codeUnits,
      ..._u32le(54), 0, 0, 0, 0, ..._u32le(54), // file header
      ..._u32le(40), ..._u32le(width), ..._u32le(height & 0xFFFFFFFF),
      ..._u16le(1), ..._u16le(24), ...List.filled(24, 0),
    ]);

Uint8List _bmpCore(int width, int height) => Uint8List.fromList([
      ..."BM".codeUnits,
      ..._u32le(26),
      0,
      0,
      0,
      0,
      ..._u32le(26),
      ..._u32le(12),
      ..._u16le(width),
      ..._u16le(height),
      ..._u16le(1),
      ..._u16le(24),
    ]);
