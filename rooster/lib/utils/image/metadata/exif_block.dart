import 'dart:typed_data';

/// Reads up to [length] bytes of a file from [offset]: fewer at its end.
typedef ByteReader = Future<Uint8List> Function(int offset, int length);

/// A [ByteReader] over bytes in memory.
ByteReader bytesReader(Uint8List bytes) =>
    (offset, length) async => offset >= bytes.length
        ? Uint8List(0)
        : Uint8List.sublistView(bytes, offset,
            offset + length > bytes.length ? bytes.length : offset + length);

/// The Exif blocks a file holds.
class ExifBlocks {
  const ExifBlocks(this.whole, {this.cut = false});

  /// Each whole block: the TIFF block, after the `Exif\0\0` of a JPEG
  /// segment, and as stored in a PNG or WebP chunk (with the prefix some
  /// writers add).
  final List<Uint8List> whole;

  /// A block cut short by the end of the file, or one the walk could not
  /// take out (larger than [maxExifBlock]), or a walk that broke before the
  /// end (a segment or chunk running past the file, bytes where a marker
  /// should be), where a block could hide past the break.
  final bool cut;
}

/// The largest Exif block taken out of a file. A JPEG's is at most 64 kB;
/// a larger one elsewhere counts as cut.
const int maxExifBlock = 4 << 20;

/// The Exif blocks of a JPEG, PNG or WebP, found by walking its segment or
/// chunk headers through
/// [read]: every APP1 `Exif` segment up to the EOI (the scans read through
/// for the markers between them), every PNG `eXIf` chunk up to IEND, every
/// WebP `EXIF` chunk up to the end of the file (each chunk followed by its
/// padding byte when its size is odd, and past the end the RIFF declares).
///
/// This is not a reader: it takes the blocks out, for when the Exif reader
/// found nothing in them (see `readExifGps`), and says whether one may be
/// missing.
Future<ExifBlocks> findExifBlocks(ByteReader read) async {
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
  return const ExifBlocks([]);
}

/// The [size] bytes at [offset], null when the file ends before their last
/// or they are more than [maxExifBlock].
Future<Uint8List?> _whole(ByteReader read, int offset, int size) async {
  if (size > maxExifBlock) return null;
  if (size <= 0) return Uint8List(0);
  final bytes = await read(offset, size);
  return bytes.length < size ? null : bytes;
}

/// [ByteReader] through a window of 64 kB, for a walk that looks at every
/// byte (a JPEG's scans and fill bytes): one read per window.
class _Window {
  _Window(this._read);

  final ByteReader _read;
  Uint8List _bytes = Uint8List(0);
  int _start = 0;

  /// Whether the window holds [count] bytes from [pos], read when it does
  /// not: false when the file ends first.
  Future<bool> _load(int pos, [int count = 1]) async {
    if (pos >= _start && pos + count <= _start + _bytes.length) return true;
    _start = pos;
    _bytes = await _read(pos, 64 << 10);
    return _bytes.length >= count;
  }

  /// The byte at [pos], null past the end of the file.
  Future<int?> at(int pos) async =>
      await _load(pos) ? _bytes[pos - _start] : null;

  /// The first position from [pos] that does not hold 0xFF, null when the
  /// file ends first.
  Future<int?> pastFill(int pos) async {
    while (await _load(pos)) {
      final bytes = _bytes;
      for (var i = pos - _start; i < bytes.length; i++) {
        if (bytes[i] != 0xFF) return _start + i;
      }
      pos = _start + bytes.length;
    }
    return null;
  }

  /// Where the entropy-coded data from [pos] ends: the first 0xFF followed
  /// by neither 0x00 (a stuffed byte) nor a restart marker, which is passed
  /// over. Null when the file ends first.
  Future<int?> markerAfter(int pos) async {
    while (await _load(pos, 2)) {
      final bytes = _bytes;
      var i = pos - _start;
      for (; i + 1 < bytes.length; i++) {
        if (bytes[i] != 0xFF) continue;
        final next = bytes[i + 1];
        if (next != 0x00 && (next < 0xD0 || next > 0xD7)) return _start + i;
        i++;
      }
      pos = _start + i; // the window's last byte, with the next window
    }
    return null;
  }
}

Future<ExifBlocks> _jpegExif(ByteReader read) async {
  final window = _Window(read);
  final blocks = <Uint8List>[];
  var pos = 2;
  while (true) {
    if (await window.at(pos) != 0xFF) return ExifBlocks(blocks, cut: true);
    // Fill bytes: any number of 0xFF before the marker.
    final at = await window.pastFill(pos + 1);
    if (at == null) return ExifBlocks(blocks, cut: true);
    final marker = (await window.at(at))!;
    final start = at + 1;
    if (marker == 0xD9) return ExifBlocks(blocks); // EOI
    if (marker == 0x01) {
      pos = start; // TEM: no length
      continue;
    }
    if (marker >= 0xD0 && marker <= 0xD7) {
      pos = start; // RSTn: no length, entropy-coded data after it
    } else {
      final segment = await read(start, 8);
      if (segment.length < 2) return ExifBlocks(blocks, cut: true);
      final length = segment[0] << 8 | segment[1];
      if (length < 2) return ExifBlocks(blocks, cut: true);
      pos = start + length;
      if (marker == 0xE1 &&
          segment.length >= 6 &&
          String.fromCharCodes(segment, 2, 6) == "Exif") {
        final block = await _whole(read, start + 8, length - 8);
        if (block == null) return ExifBlocks(blocks, cut: true);
        blocks.add(block);
      }
      if (marker != 0xDA) continue;
    }
    // After SOS or RSTn, entropy-coded data up to the next marker.
    final end = await window.markerAfter(pos);
    if (end == null) return ExifBlocks(blocks); // the file ends in it
    pos = end;
  }
}

Future<ExifBlocks> _pngExif(ByteReader read) async {
  final blocks = <Uint8List>[];
  var pos = 8;
  while (true) {
    final header = await read(pos, 8);
    if (header.isEmpty) return ExifBlocks(blocks); // the end, between chunks
    if (header.length < 8) return ExifBlocks(blocks, cut: true);
    final length = ByteData.sublistView(header).getUint32(0);
    final type = String.fromCharCodes(header, 4, 8);
    if (type == "eXIf") {
      final block = await _whole(read, pos + 8, length);
      if (block == null) return ExifBlocks(blocks, cut: true);
      blocks.add(block);
    }
    if (type == "IEND") return ExifBlocks(blocks);
    pos += 12 + length;
  }
}

Future<ExifBlocks> _webpExif(ByteReader read) async {
  final riff = await read(4, 4);
  final end = 8 + ByteData.sublistView(riff).getUint32(0, Endian.little);
  final blocks = <Uint8List>[];
  var pos = 12;
  // To the end of the file: readers find an EXIF past the end the RIFF
  // declares.
  while (true) {
    final header = await read(pos, 8);
    // The end of the file: cut when the RIFF runs past it.
    if (header.length < 8) return ExifBlocks(blocks, cut: pos < end);
    final size = ByteData.sublistView(header).getUint32(4, Endian.little);
    if (String.fromCharCodes(header, 0, 4) == "EXIF") {
      final block = await _whole(read, pos + 8, size);
      if (block == null) return ExifBlocks(blocks, cut: true);
      blocks.add(block);
    }
    pos += 8 + size + (size & 1);
  }
}
