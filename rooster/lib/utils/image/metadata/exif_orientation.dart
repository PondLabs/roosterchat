import 'dart:typed_data';

/// The Exif orientation that leaves a picture as it is stored.
const int exifOrientationNormal = 1;

const int _orientationTag = 0x0112;
const int _typeShort = 3;

/// The pointer from IFD0 to the Exif sub-IFD.
const int _exifIfdTag = 0x8769;

/// Reads the Orientation tag (0x0112) from IFD0 of a TIFF block, the body
/// of an Exif segment after its `Exif\0\0` prefix.
///
/// Read the way Flutter's engine reads it, since the rewrite has to keep the
/// picture drawn as the original is: the header's magic number (42) is not
/// checked, and the first Orientation entry that is a SHORT with a count of
/// 1 and a value from 1 to 8 counts; any other Orientation entry is passed
/// over. Returns [exifOrientationNormal] when the block is malformed or has
/// no such entry.
///
/// Returns null, so the file counts as one that does not parse and goes to
/// the fallback (which draws it with the engine), when the block cannot be
/// read the way the engine reads it:
/// - IFD0 does not fit in the block (its entries and the 4-byte offset of
///   the next IFD): such a block can be shorter than the one a rewrite
///   writes back;
/// - IFD0 starts inside the 8-byte header, where the engine still looks
///   for an orientation;
/// - IFD0 points (tag 0x8769) to an Exif sub-IFD that holds an Orientation
///   tag, which the engine applies too, or that does not fit in the block.
///   A camera's sub-IFD (exposure, dates) holds none and is passed over.
int? readTiffOrientation(Uint8List tiff) {
  if (tiff.length < 8) return exifOrientationNormal;
  final Endian endian;
  if (tiff[0] == 0x49 && tiff[1] == 0x49) {
    endian = Endian.little;
  } else if (tiff[0] == 0x4D && tiff[1] == 0x4D) {
    endian = Endian.big;
  } else {
    return exifOrientationNormal;
  }
  final data = ByteData.sublistView(tiff);
  final ifd = data.getUint32(4, endian);
  if (ifd < 8) return null;
  if (ifd + 2 > tiff.length) return null;
  final count = data.getUint16(ifd, endian);
  if (ifd + 2 + count * 12 + 4 > tiff.length) return null;
  int? orientation;
  for (var i = 0; i < count; i++) {
    final entry = ifd + 2 + i * 12;
    final tag = data.getUint16(entry, endian);
    if (tag == _exifIfdTag) {
      final subIfd = data.getUint32(entry + 8, endian);
      if (!_subIfdHasNoOrientation(data, subIfd, endian)) return null;
      continue;
    }
    if (orientation != null || tag != _orientationTag) continue;
    if (data.getUint16(entry + 2, endian) != _typeShort) continue;
    if (data.getUint32(entry + 4, endian) != 1) continue;
    final value = data.getUint16(entry + 8, endian);
    if (value >= 1 && value <= 8) orientation = value;
  }
  return orientation ?? exifOrientationNormal;
}

/// Whether the Exif sub-IFD at [offset] fits in the block and holds no
/// Orientation entry, of any type.
bool _subIfdHasNoOrientation(ByteData data, int offset, Endian endian) {
  if (offset + 2 > data.lengthInBytes) return false;
  final count = data.getUint16(offset, endian);
  if (offset + 2 + count * 12 > data.lengthInBytes) return false;
  for (var i = 0; i < count; i++) {
    if (data.getUint16(offset + 2 + i * 12, endian) == _orientationTag) {
      return false;
    }
  }
  return true;
}

/// Whether an Exif payload starts with the `Exif\0\0` prefix. JPEG APP1
/// always has it; in PNG and WebP the standards say raw TIFF, but some
/// writers (Pillow among them) add it, and some decoders then skip the
/// block, Flutter's WebP decoder for one.
bool hasExifPrefix(Uint8List exif) =>
    exif.length >= 6 &&
    exif[0] == 0x45 && // E
    exif[1] == 0x78 && // x
    exif[2] == 0x69 && // i
    exif[3] == 0x66 && // f
    exif[4] == 0 &&
    exif[5] == 0;

/// Reads the orientation from an Exif payload, with or without the
/// `Exif\0\0` prefix. Null, as in [readTiffOrientation], when IFD0 does
/// not fit.
int? readExifOrientation(Uint8List exif) => readTiffOrientation(
    hasExifPrefix(exif) ? Uint8List.sublistView(exif, 6) : exif);

/// [minimalOrientationTiff], behind the `Exif\0\0` prefix when [prefixed]:
/// a rewrite writes the block the way the original did, so every decoder
/// reads it (or skips it) as it did the original's.
Uint8List minimalOrientationExif(int orientation, {required bool prefixed}) {
  final tiff = minimalOrientationTiff(orientation);
  if (!prefixed) return tiff;
  return Uint8List.fromList([0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff]);
}

/// A 26-byte big-endian TIFF block whose only tag is Orientation: what the
/// rewrite writes back when a picture is not stored the way it is shown.
Uint8List minimalOrientationTiff(int orientation) {
  assert(orientation >= 1 && orientation <= 8);
  final out = ByteData(26)
    ..setUint8(0, 0x4D) // MM: big-endian
    ..setUint8(1, 0x4D)
    ..setUint16(2, 42)
    ..setUint32(4, 8) // IFD0 right after the header
    ..setUint16(8, 1) // one entry
    ..setUint16(10, _orientationTag)
    ..setUint16(12, _typeShort)
    ..setUint32(14, 1) // count
    ..setUint16(18, orientation) // value, left-justified in its 4 bytes
    ..setUint32(22, 0); // no next IFD
  return out.buffer.asUint8List();
}
