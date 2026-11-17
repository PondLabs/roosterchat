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
  /// segment or the offset of a HEIF item, and as stored in a PNG or WebP
  /// chunk (with the prefix some writers add).
  final List<Uint8List> whole;

  /// A block cut short by the end of the file, or one the walk could not
  /// take out (larger than [maxExifBlock], or where a HEIF puts it out of
  /// reach), or a walk that broke before the end (a segment, chunk or box
  /// running past the file, bytes where a marker should be), where a block
  /// could hide past the break.
  final bool cut;
}

/// The largest Exif block taken out of a file. A JPEG's is at most 64 kB;
/// a larger one elsewhere counts as cut.
const int maxExifBlock = 4 << 20;

/// The Exif blocks of a JPEG, PNG, WebP or HEIF (HEIC or AVIF of any
/// brand), found by walking its segment, chunk or box headers through
/// [read]: every APP1 `Exif` segment up to the EOI (the scans read through
/// for the markers between them), every PNG `eXIf` chunk up to IEND, every
/// WebP `EXIF` chunk up to the end of the file (each chunk followed by its
/// padding byte when its size is odd, and past the end the RIFF declares),
/// and every HEIF item of type `Exif` in the top-level `meta` box.
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
  if (head.length >= 12 && String.fromCharCodes(head, 4, 8) == "ftyp") {
    return _heifExif(read, head);
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

/// The brands of a HEIF still or sequence (HEIC, AVIF and the others).
const _heifBrands = {
  "mif1", "mif2", "msf1", "miaf", "heic", "heix", "heim", "heis", "hevc", //
  "hevx", "heif", "avif", "avis",
};

/// A box, header or field that runs past what holds it.
class _Malformed implements Exception {
  const _Malformed();
}

/// The big-endian unsigned integer of [size] bytes at [at] in [b].
int _uint(Uint8List b, int at, int size) {
  if (at < 0 || at + size > b.length) throw const _Malformed();
  var value = 0;
  for (var i = 0; i < size; i++) {
    value = value * 256 + b[at + i];
  }
  return value;
}

/// The boxes in [b] from [from] to [to], as (type, body start, end).
List<(String, int, int)> _boxes(Uint8List b, int from, int to) {
  final out = <(String, int, int)>[];
  var pos = from;
  while (pos + 8 <= to) {
    var size = _uint(b, pos, 4);
    var body = pos + 8;
    if (size == 1) {
      size = _uint(b, pos + 8, 8);
      body = pos + 16;
    } else if (size == 0) {
      size = to - pos;
    }
    if (size < body - pos || pos + size > to) throw const _Malformed();
    out.add((String.fromCharCodes(b, pos + 4, pos + 8), body, pos + size));
    pos += size;
  }
  return out;
}

Future<ExifBlocks> _heifExif(ByteReader read, Uint8List head) async {
  final ftypSize = _uint(head, 0, 4);
  final ftyp = await read(0, ftypSize > 4096 ? 0 : ftypSize);
  if (ftyp.length < 16 || ftyp.length < ftypSize) return const ExifBlocks([]);
  final brands = {
    for (var at = 8; at + 4 <= ftypSize; at += at == 8 ? 8 : 4)
      String.fromCharCodes(ftyp, at, at + 4),
  };
  if (brands.intersection(_heifBrands).isEmpty) return const ExifBlocks([]);
  var pos = ftypSize;
  while (true) {
    final header = await read(pos, 16);
    if (header.isEmpty) return const ExifBlocks([]); // no meta box
    if (header.length < 8) return const ExifBlocks([], cut: true);
    var size = _uint(header, 0, 4);
    var body = 8;
    if (size == 1 && header.length == 16) {
      size = _uint(header, 8, 8);
      body = 16;
    }
    final type = String.fromCharCodes(header, 4, 8);
    // Size 0: the box runs to the end of the file.
    if (size == 0) return ExifBlocks(const [], cut: type == "meta");
    if (size < body) return const ExifBlocks([], cut: true);
    if (type == "meta") {
      final meta = await _whole(read, pos + body, size - body);
      if (meta == null) return const ExifBlocks([], cut: true);
      try {
        return await _heifItems(read, meta);
      } on _Malformed {
        return const ExifBlocks([], cut: true);
      }
    }
    pos += size;
  }
}

/// The Exif items of a HEIF `meta` box (its body, [meta]): their ids from
/// `iinf`, where they are from `iloc`.
Future<ExifBlocks> _heifItems(ByteReader read, Uint8List meta) async {
  final exifItems = <int>{};
  (int, int)? iloc;
  for (final (type, body, end) in _boxes(meta, 4, meta.length)) {
    if (type == "iinf") {
      final count = _uint(meta, body, 1) == 0 ? 2 : 4;
      for (final (type, at, end) in _boxes(meta, body + 4 + count, end)) {
        final version = _uint(meta, at, 1);
        if (type != "infe" || version < 2) continue; // no item_type before 2
        final id = version == 2 ? 2 : 4;
        final itemType = at + 4 + id + 2;
        if (itemType + 4 > end) throw const _Malformed();
        if (String.fromCharCodes(meta, itemType, itemType + 4) == "Exif") {
          exifItems.add(_uint(meta, at + 4, id));
        }
      }
    } else if (type == "iloc") {
      iloc = (body, end);
    }
  }
  // Read after iinf, which can come after it: only the Exif items' places
  // are kept.
  final places = iloc == null
      ? const <int, (int, List<(int, int)>)>{}
      : _itemLocations(meta, iloc.$1, iloc.$2, exifItems);
  final blocks = <Uint8List>[];
  for (final item in exifItems) {
    // In the file (construction method 0), in extents of a known length.
    final (method, extents) = places[item] ?? (-1, const <(int, int)>[]);
    if (method != 0 || extents.isEmpty) return ExifBlocks(blocks, cut: true);
    // At most maxExifBlock in all, however many extents hold it.
    final size = extents.fold(0, (size, extent) => size + extent.$2);
    if (size > maxExifBlock) return ExifBlocks(blocks, cut: true);
    final data = BytesBuilder(copy: false);
    for (final (offset, length) in extents) {
      final bytes = length == 0 ? null : await _whole(read, offset, length);
      if (bytes == null) return ExifBlocks(blocks, cut: true);
      data.add(bytes);
    }
    // The item starts with the offset of the TIFF header after it.
    final bytes = data.takeBytes();
    final tiff = bytes.length < 4 ? -1 : 4 + _uint(bytes, 0, 4);
    if (tiff < 0 || tiff > bytes.length) return ExifBlocks(blocks, cut: true);
    blocks.add(Uint8List.sublistView(bytes, tiff));
  }
  return ExifBlocks(blocks);
}

/// Big-endian fields of [b], read one after another from [at] up to [end].
class _Fields {
  _Fields(this.b, this.at, this.end);

  final Uint8List b;
  int at;
  final int end;

  int next(int size) {
    if (at + size > end) throw const _Malformed();
    final value = _uint(b, at, size);
    at += size;
    return value;
  }

  /// Whether [count] records of [size] bytes each fit in what is left:
  /// a record that takes no byte never fits, so a count read from the file
  /// cannot make records out of nothing.
  bool fits(int count, int size) =>
      count == 0 || (size > 0 && count * size <= end - at);
}

/// The places an `iloc` box (its body from [at] to [end] in [b]) gives the
/// items of [wanted], by id: their construction method and their extents,
/// as (file offset, length). Every item is checked to fit in the box.
Map<int, (int, List<(int, int)>)> _itemLocations(
    Uint8List b, int at, int end, Set<int> wanted) {
  final fields = _Fields(b, at, end);
  final version = fields.next(4) >> 24;
  final sizes = fields.next(2);
  final offsetSize = sizes >> 12, lengthSize = sizes >> 8 & 0xF;
  final baseSize = sizes >> 4 & 0xF, indexSize = version > 0 ? sizes & 0xF : 0;
  final id = version < 2 ? 2 : 4;
  final extentSize = indexSize + offsetSize + lengthSize;
  final count = fields.next(id);
  // An item takes its id, method, data reference, base and extent count.
  if (!fields.fits(count, id + (version > 0 ? 2 : 0) + 4 + baseSize)) {
    throw const _Malformed();
  }
  final places = <int, (int, List<(int, int)>)>{};
  for (var i = 0; i < count; i++) {
    final item = fields.next(id);
    final method = version > 0 ? fields.next(2) & 0xF : 0;
    fields.next(2); // data_reference_index
    final base = fields.next(baseSize);
    final extents = fields.next(2);
    if (!fields.fits(extents, extentSize)) throw const _Malformed();
    if (!wanted.contains(item)) {
      fields.at += extents * extentSize;
      continue;
    }
    final list = <(int, int)>[];
    for (var n = 0; n < extents; n++) {
      fields.next(indexSize);
      final offset = fields.next(offsetSize);
      list.add((base + offset, fields.next(lengthSize)));
    }
    places[item] = (method, list);
  }
  return places;
}
