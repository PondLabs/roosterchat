import 'dart:typed_data';

import 'package:rooster/utils/image/metadata/exif_orientation.dart';

/// What an Exif block says about where a picture was taken.
enum ExifGps {
  /// Its IFDs hold no pointer to a GPS IFD.
  none,

  /// An IFD points to a GPS IFD (tag 0x8825), as the Exif reader's
  /// `GPSInfo` tag shows it.
  found,

  /// IFD0, or an Exif sub-IFD one of the IFDs points to, cannot be read:
  /// the block may hold a location another reader finds.
  unreadable,
}

/// The pointer from an IFD to the GPS IFD.
const int _gpsIfdTag = 0x8825;

/// The pointer from an IFD to the Exif sub-IFD, where some writers put the
/// GPS pointer too.
const int _exifIfdTag = 0x8769;

/// The pointer from the Exif sub-IFD to the Interop IFD.
const int _interopIfdTag = 0xA005;

/// How many IFDs of the chain from IFD0 are looked into (IFD0, IFD1 and
/// any after them, which the Exif reader reads too).
const int _maxIfds = 8;

/// Whether the Exif block [exif] (a TIFF block, with or without the
/// `Exif\0\0` prefix) points to a GPS IFD: from the block alone, for when
/// the Exif reader found it but could not get to it (behind an odd-sized
/// WebP chunk, after a scan, behind another Exif block).
///
/// Every IFD of the chain from IFD0 is looked into, the way the Exif reader
/// reads them, and so is the Exif sub-IFD each points to (tag 0x8769), and
/// the Interop IFD under that (tag 0xA005). A
/// GPS pointer of any type counts. IFD0 has to fit in the block; an IFD of
/// the chain after it that does not ends the chain. An Exif sub-IFD that
/// does not fit, or whose pointer is zero or points back (to its own IFD or
/// before it), makes the block unreadable unless a GPS pointer is found
/// elsewhere; so does an Interop pointer that points back.
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
  // The entry count of the IFD at [at], null when it does not fit.
  int? entries(int at) {
    if (at < 8 || at + 2 > tiff.length) return null;
    final count = data.getUint16(at, endian);
    return at + 2 + count * 12 <= tiff.length ? count : null;
  }

  // What the first entry of [tag] in the IFD at [ifd] holds (an offset, for
  // a pointer), null without one.
  int? pointer(int ifd, int count, int tag) {
    for (var i = 0; i < count; i++) {
      final entry = ifd + 2 + i * 12;
      if (data.getUint16(entry, endian) == tag) {
        return data.getUint32(entry + 8, endian);
      }
    }
    return null;
  }

  // The entry count of the sub-IFD at [sub] that the IFD at [parent]
  // points to, null when it does not fit or points back.
  int? subEntries(int parent, int sub) => sub <= parent ? null : entries(sub);

  var unreadable = false;
  var ifd = data.getUint32(4, endian);
  final seen = <int>{};
  for (var n = 0; n < _maxIfds && seen.add(ifd); n++) {
    final count = entries(ifd);
    if (count == null) {
      if (n == 0) return ExifGps.unreadable;
      break;
    }
    if (pointer(ifd, count, _gpsIfdTag) != null) return ExifGps.found;
    final sub = pointer(ifd, count, _exifIfdTag);
    if (sub != null) {
      final subCount = subEntries(ifd, sub);
      if (subCount == null) {
        unreadable = true;
      } else {
        if (pointer(sub, subCount, _gpsIfdTag) != null) return ExifGps.found;
        // The Interop IFD under it is looked into for a GPS pointer too. A
        // pointer to it that points back makes the block unreadable, as the
        // sub-IFD's does; one that is zero or past the block is passed over.
        final interop = pointer(sub, subCount, _interopIfdTag) ?? 0;
        if (interop != 0 && interop <= sub) {
          unreadable = true;
        } else {
          final interopCount = interop == 0 ? null : entries(interop);
          if (interopCount != null &&
              pointer(interop, interopCount, _gpsIfdTag) != null) {
            return ExifGps.found;
          }
        }
      }
    }
    final next = ifd + 2 + count * 12;
    if (next + 4 > tiff.length) break;
    ifd = data.getUint32(next, endian);
    if (ifd == 0) break;
  }
  return unreadable ? ExifGps.unreadable : ExifGps.none;
}
