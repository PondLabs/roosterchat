import 'dart:typed_data';

/// The Exif orientation that leaves a picture as it is stored.
const int exifOrientationNormal = 1;

const int _orientationTag = 0x0112;
const int _typeShort = 3;

/// Reads the Orientation tag (0x0112) from IFD0 of a TIFF block, the body
/// of an Exif segment after its `Exif\0\0` prefix.
///
/// Returns 1 to 8, or [exifOrientationNormal] when the block is malformed,
/// has no such tag, or holds a value outside 1 to 8: that is how decoders
/// draw such a picture, so it is what the rewrite has to keep.
int readTiffOrientation(Uint8List tiff) {
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
  if (data.getUint16(2, endian) != 42) return exifOrientationNormal;
  final ifd = data.getUint32(4, endian);
  if (ifd < 8 || ifd + 2 > tiff.length) return exifOrientationNormal;
  final count = data.getUint16(ifd, endian);
  for (var i = 0; i < count; i++) {
    final entry = ifd + 2 + i * 12;
    if (entry + 12 > tiff.length) break;
    if (data.getUint16(entry, endian) != _orientationTag) continue;
    if (data.getUint16(entry + 2, endian) != _typeShort) break;
    final value = data.getUint16(entry + 8, endian);
    return value >= 1 && value <= 8 ? value : exifOrientationNormal;
  }
  return exifOrientationNormal;
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
/// `Exif\0\0` prefix.
int readExifOrientation(Uint8List exif) => readTiffOrientation(
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
