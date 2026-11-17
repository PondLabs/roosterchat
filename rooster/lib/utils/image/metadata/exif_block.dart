import 'dart:typed_data';

/// Reads up to [length] bytes of a file from [offset]: fewer at its end.
typedef ByteReader = Future<Uint8List> Function(int offset, int length);

/// A [ByteReader] over bytes in memory.
ByteReader bytesReader(Uint8List bytes) =>
    (offset, length) async => offset >= bytes.length
        ? Uint8List(0)
        : Uint8List.sublistView(bytes, offset,
            offset + length > bytes.length ? bytes.length : offset + length);

/// What a file holds of an Exif block.
enum ExifBlock {
  /// None: not a JPEG, PNG or WebP, or one without an Exif block.
  none,

  /// A whole Exif block.
  whole,

  /// An Exif block cut short by the end of the file, or a walk that broke
  /// before the end (a segment or chunk running past the file, bytes where
  /// a marker should be), where a block could hide past the break.
  cut,
}

/// The Exif block of a JPEG, PNG or WebP, found by walking its segment or
/// chunk headers (only those are read, through [read]): an APP1 `Exif`
/// segment before the first scan, a PNG `eXIf` chunk, a WebP `EXIF` chunk
/// (each chunk followed by its padding byte when its size is odd).
///
/// This is not a reader: it says the block is there, for when the Exif
/// reader found nothing in it, and whether it is whole.
Future<ExifBlock> findExifBlock(ByteReader read) async {
  final head = await read(0, 12);
  if (head.length >= 3 && head[0] == 0xFF && head[1] == 0xD8) {
    return _jpegExif(read);
  }
  if (head.length >= 8 &&
      head[0] == 0x89 &&
      String.fromCharCodes(head, 1, 4) == "PNG") {
    return _pngExif(read);
  }
  if (head.length >= 12 &&
      String.fromCharCodes(head, 0, 4) == "RIFF" &&
      String.fromCharCodes(head, 8, 12) == "WEBP") {
    return _webpExif(read);
  }
  return ExifBlock.none;
}

/// Whole when the file has a byte at [end] - 1, the block's last.
Future<ExifBlock> _ends(ByteReader read, int end) async =>
    (await read(end - 1, 1)).isEmpty ? ExifBlock.cut : ExifBlock.whole;

Future<ExifBlock> _jpegExif(ByteReader read) async {
  var pos = 2;
  while (true) {
    final header = await read(pos, 10);
    if (header.length < 2 || header[0] != 0xFF) return ExifBlock.cut;
    var at = 1;
    // Fill bytes: any number of 0xFF before the marker.
    while (at < header.length && header[at] == 0xFF) {
      at++;
    }
    if (at >= header.length) {
      pos += at - 1; // keep one 0xFF to start the next read
      continue;
    }
    final marker = header[at];
    final start = pos + at + 1;
    if (marker == 0xDA || marker == 0xD9) return ExifBlock.none; // SOS, EOI
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      pos = start; // TEM, RSTn: no length
      continue;
    }
    final segment = await read(start, 8);
    if (segment.length < 2) return ExifBlock.cut;
    final length = segment[0] << 8 | segment[1];
    if (length < 2) return ExifBlock.cut;
    if (marker == 0xE1 &&
        segment.length >= 6 &&
        String.fromCharCodes(segment, 2, 6) == "Exif") {
      return _ends(read, start + length);
    }
    pos = start + length;
  }
}

Future<ExifBlock> _pngExif(ByteReader read) async {
  var pos = 8;
  while (true) {
    final header = await read(pos, 8);
    if (header.isEmpty) return ExifBlock.none; // the end, between chunks
    if (header.length < 8) return ExifBlock.cut;
    final length = ByteData.sublistView(header).getUint32(0);
    final type = String.fromCharCodes(header, 4, 8);
    if (type == "eXIf") return _ends(read, pos + 8 + length);
    if (type == "IEND") return ExifBlock.none;
    pos += 12 + length;
  }
}

Future<ExifBlock> _webpExif(ByteReader read) async {
  final riff = await read(4, 4);
  final end = 8 + ByteData.sublistView(riff).getUint32(0, Endian.little);
  var pos = 12;
  while (pos < end) {
    final header = await read(pos, 8);
    // The RIFF length runs past the file.
    if (header.length < 8) return ExifBlock.cut;
    final size = ByteData.sublistView(header).getUint32(4, Endian.little);
    if (String.fromCharCodes(header, 0, 4) == "EXIF") {
      return _ends(read, pos + 8 + size);
    }
    pos += 8 + size + (size & 1);
  }
  return ExifBlock.none;
}
