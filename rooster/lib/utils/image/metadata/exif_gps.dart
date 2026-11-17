import 'dart:typed_data';

import 'package:rooster/utils/image/metadata/exif_orientation.dart';

/// What an Exif block says about where a picture was taken.
enum ExifGps {
  /// Its IFDs hold no pointer to a GPS IFD.
  none,

  /// An IFD points to a GPS IFD (tag 0x8825), as the Exif reader's
  /// `GPSInfo` tag shows it.
  found,

  /// IFD0 cannot be read: the block may hold a location another reader
  /// finds.
  unreadable,
}

/// The pointer from an IFD to the GPS IFD.
const int _gpsIfdTag = 0x8825;

/// How many IFDs of the chain from IFD0 are looked into (IFD0, IFD1 and
/// any after them, which the Exif reader reads too).
const int _maxIfds = 8;

/// Whether the Exif block [exif] (a TIFF block, with or without the
/// `Exif\0\0` prefix) points to a GPS IFD: from the block alone, for when
/// the Exif reader found it but could not get to it (behind an odd-sized
/// WebP chunk, after a scan, behind another Exif block).
///
/// Every IFD of the chain from IFD0 is looked into, the way the Exif reader
/// reads them, and a GPS pointer of any type counts. IFD0 has to fit in the
/// block; an IFD after it that does not ends the chain.
ExifGps readExifGps(Uint8List exif) {
  final tiff = hasExifPrefix(exif) ? Uint8List.sublistView(exif, 6) : exif;
  if (tiff.length < 8) return ExifGps.unreadable;
  final Endian endian;
  if (tiff[0] == 0x49 && tiff[1] == 0x49) {
    endian = Endian.little;
  } else if (tiff[0] == 0x4D && tiff[1] == 0x4D) {
    endian = Endian.big;
  } else {
    return ExifGps.unreadable;
  }
  final data = ByteData.sublistView(tiff);
  var ifd = data.getUint32(4, endian);
  final seen = <int>{};
  for (var n = 0; n < _maxIfds && seen.add(ifd); n++) {
    final fits = ifd >= 8 &&
        ifd + 2 <= tiff.length &&
        ifd + 2 + data.getUint16(ifd, endian) * 12 <= tiff.length;
    if (!fits) return n == 0 ? ExifGps.unreadable : ExifGps.none;
    final count = data.getUint16(ifd, endian);
    for (var i = 0; i < count; i++) {
      if (data.getUint16(ifd + 2 + i * 12, endian) == _gpsIfdTag) {
        return ExifGps.found;
      }
    }
    final next = ifd + 2 + count * 12;
    if (next + 4 > tiff.length) break;
    ifd = data.getUint32(next, endian);
    if (ifd == 0) break;
  }
  return ExifGps.none;
}
