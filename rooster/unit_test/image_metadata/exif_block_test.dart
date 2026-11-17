@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/utils/image/metadata/exif_block.dart';
import 'package:rooster/utils/image/metadata/exif_gps.dart';
import 'package:rooster/utils/image/metadata/exif_orientation.dart';

/// The Exif block finder (`exif_block.dart`) and the answer Send acts on
/// for the files it walks: blocks the Exif reader misses are looked into
/// for a GPS pointer (`exif_gps.dart`), so a file with a location gets the
/// location question, and one whose block reads without a location gets
/// none.
void main() {
  const fixtures = 'unit_test/fixtures/image_metadata';
  Uint8List fixture(String name) => File('$fixtures/$name').readAsBytesSync();
  Uint8List cat(List<List<int>> parts) =>
      Uint8List.fromList([for (final p in parts) ...p]);

  // The fixture's Exif: its APP1 segment (SOI, APP0 JFIF, then APP1) and
  // the TIFF block in it, GPS and all.
  final gps = fixture('gps_exif.jpg');
  final soi = gps.sublist(0, 2);
  final app0End = 4 + (gps[4] << 8 | gps[5]);
  final app1End = app0End + 2 + (gps[app0End + 2] << 8 | gps[app0End + 3]);
  final app1 = Uint8List.sublistView(gps, app0End, app1End);
  final rest = Uint8List.sublistView(gps, app1End);
  final tiff = Uint8List.sublistView(app1, 10);
  Uint8List segment(int marker, List<int> payload) => cat([
        [0xFF, marker, (payload.length + 2) >> 8, (payload.length + 2) & 0xFF],
        payload,
      ]);
  // A readable Exif with one tag, the orientation: no location.
  final smallExif = segment(0xE1, minimalOrientationExif(6, prefixed: true));
  final plain = img.encodeJpg(img.Image(width: 16, height: 16));

  Uint8List chunk(String type, List<int> payload) => cat([
        type.codeUnits,
        (ByteData(4)..setUint32(0, payload.length, Endian.little))
            .buffer
            .asUint8List(),
        payload,
        if (payload.length.isOdd) [0],
      ]);
  // A WebP of [chunks], its RIFF size [riff] when given (else the true one).
  Uint8List webp(List<List<int>> chunks, {int? riff}) {
    final body = cat(['WEBP'.codeUnits, ...chunks]);
    return cat([
      'RIFF'.codeUnits,
      (ByteData(4)..setUint32(0, riff ?? body.length, Endian.little))
          .buffer
          .asUint8List(),
      body,
    ]);
  }

  // An image chunk of odd size, so a padding byte follows it: the Exif
  // reader does not count that byte and misses what comes after.
  final oddImage = chunk('VP8L', Uint8List(439));
  final exifChunk = chunk('EXIF', tiff);

  Uint8List png(List<List<int>> beforeIdat, {List<int> afterIdat = const []}) {
    final source = img.encodePng(img.Image(width: 8, height: 8));
    final ihdrEnd = 8 + 12 + 13;
    return cat([
      Uint8List.sublistView(source, 0, ihdrEnd),
      ...beforeIdat,
      Uint8List.sublistView(source, ihdrEnd, source.length - 12),
      afterIdat,
      Uint8List.sublistView(source, source.length - 12),
    ]);
  }

  Uint8List pngChunk(String type, List<int> payload) => cat([
        (ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List(),
        type.codeUnits,
        payload,
        [0, 0, 0, 0], // the CRC: no reader here checks it
      ]);

  late Directory dir;
  var files = 0;
  setUp(() => dir = Directory.systemTemp.createTempSync('t616_exif_block'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // The exif package leaves a file it fails to read open.
    }
  });

  /// The answer for [bytes] in memory, checked to be the same from disk.
  Future<LocationAnswer> answer(Uint8List bytes) async {
    final memory =
        await PendingFileAttachment(name: 'a', data: bytes).locationCheck();
    final path = '${dir.path}/file${files++}';
    File(path).writeAsBytesSync(bytes);
    final disk =
        await PendingFileAttachment(name: 'a', path: path).locationCheck();
    expect(disk, memory, reason: 'from disk as from memory');
    return memory;
  }

  Future<bool> readerSeesGps(Uint8List bytes) async =>
      (await readExifFromBytes(bytes))
          .keys
          .any((k) => k.toLowerCase().contains('gps'));

  group('a block with GPS that the Exif reader misses gets the question', () {
    // The review's probe, cases 21, 23, 35, 37 and 38.
    final cases = <(String, Uint8List)>[
      (
        'a small readable Exif, then the Exif with GPS',
        cat([soi, smallExif, app1, rest])
      ),
      (
        'the Exif only after the scan, before EOI',
        cat([
          plain.sublist(0, plain.length - 2),
          app1,
          [0xFF, 0xD9]
        ])
      ),
      (
        'a WebP whose RIFF size ends before the EXIF',
        webp([oddImage, exifChunk], riff: 4 + oddImage.length)
      ),
      ('a WebP with RIFF size 0', webp([oddImage, exifChunk], riff: 0)),
      (
        'a WebP with RIFF size 4 (only "WEBP")',
        webp([oddImage, exifChunk], riff: 4)
      ),
    ];
    for (final (label, bytes) in cases) {
      test(label, () async {
        expect(await readerSeesGps(bytes), isFalse,
            reason: 'the reader alone would send it without a question');
        expect(await answer(bytes), LocationAnswer.found);
      });
    }
  });

  group('the JPEG walk', () {
    // Fill bytes, any number of 0xFF before a marker: the review's probe,
    // cases 4 to 7.
    for (final (label, bytes) in [
      (
        'one fill byte',
        cat([
          soi,
          [0xFF],
          app1,
          rest
        ])
      ),
      ('9 fill bytes', cat([soi, List.filled(9, 0xFF), app1, rest])),
      ('40 fill bytes', cat([soi, List.filled(40, 0xFF), app1, rest])),
      (
        'JFIF, then 23 fill bytes',
        cat([gps.sublist(0, app0End), List.filled(23, 0xFF), app1, rest])
      ),
    ]) {
      test('$label before the Exif: the block is found', () async {
        final blocks = await findExifBlocks(bytesReader(bytes));
        expect(blocks.cut, isFalse);
        expect(blocks.whole, [tiff]);
        expect(await answer(bytes), LocationAnswer.found);
      });
    }

    test('reads a scan through its stuffed bytes and restart markers',
        () async {
      final scan = cat([
        soi,
        segment(0xDA, [1, 1, 0, 0, 63, 0]),
        [7, 0xFF, 0x00, 7, 0xFF, 0xD3, 7, 0xFF, 0xFF, 0xD4, 7],
        segment(0xDA, [1, 1, 0, 0, 63, 0]), // a second scan
        [7, 7],
        app1,
        [0xFF, 0xD9],
        app1, // after the EOI: another file's
      ]);
      final blocks = await findExifBlocks(bytesReader(scan));
      expect(blocks.cut, isFalse);
      expect(blocks.whole, [tiff]);
    });

    test(
        'a scan of 4 MB is read 64 kB at a time, its stuffed bytes across '
        'the edges', () async {
      // 7, FF, 00 over and over: in three shifts, a stuffed byte falls on
      // the edge of a window.
      final data = Uint8List(4 << 20);
      for (var i = 0; i + 2 < data.length; i += 3) {
        data
          ..[i] = 7
          ..[i + 1] = 0xFF;
      }
      for (final shift in [0, 1, 2]) {
        final bytes = cat([
          soi,
          segment(0xFE, List.filled(shift + 1, 0x41)), // a comment
          segment(0xDA, [1, 1, 0, 0, 63, 0]),
          data,
          app1,
          [0xFF, 0xD9],
        ]);
        var reads = 0;
        final inner = bytesReader(bytes);
        final blocks = await findExifBlocks((offset, length) {
          reads++;
          return inner(offset, length);
        });
        expect(blocks.cut, isFalse, reason: 'shift $shift');
        expect(blocks.whole, [tiff], reason: 'shift $shift');
        expect(reads, lessThan(80), reason: 'shift $shift');
      }
    });

    test(
        'a walk of 4 MB from memory lets the event loop run: on the web it '
        'shares the interface thread', () async {
      final bytes = cat([
        soi,
        segment(0xDA, [1, 1, 0, 0, 63, 0]),
        Uint8List(4 << 20),
        [0xFF, 0xD9],
      ]);
      var timerRan = false;
      Timer.run(() => timerRan = true);
      bool? ranBeforeTheEnd;
      await findExifBlocks(bytesReader(bytes))
          .then((_) => ranBeforeTheEnd = timerRan);
      expect(ranBeforeTheEnd, isTrue);
    });

    test('a JPEG without Exif and a readable Exif without GPS: no question',
        () async {
      expect(await answer(plain), LocationAnswer.none);
      final small = cat([soi, smallExif, plain.sublist(2)]);
      expect((await findExifBlocks(bytesReader(small))).whole, hasLength(1));
      expect(await answer(small), LocationAnswer.none);
    });

    test('1 MB of fill bytes after the SOI, from disk: answered in 200 ms',
        () async {
      final bytes = cat([soi, List.filled(1 << 20, 0xFF)]);
      var reads = 0;
      final inner = bytesReader(bytes);
      final blocks = await findExifBlocks((offset, length) {
        reads++;
        return inner(offset, length);
      });
      expect(blocks.cut, isTrue, reason: 'no marker before the end');
      expect(reads, lessThan(20), reason: 'one read per 64 kB');

      final path = '${dir.path}/fill.jpg';
      File(path).writeAsBytesSync(bytes);
      final watch = Stopwatch()..start();
      final answer =
          await PendingFileAttachment(name: 'a', path: path).locationCheck();
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 200)));
      expect(answer, LocationAnswer.unreadable);
    });
  });

  group('100,000 empty segments, chunks or boxes', () {
    // Each walk reads its headers through a window: a read per 64 kB, not
    // one per header, and no wait for a header the window holds.
    final count = 100000;
    final png = img.encodePng(img.Image(width: 8, height: 8));
    for (final (label, bytes) in [
      (
        'JPEG comments',
        cat([
          soi,
          for (var i = 0; i < count; i++) [0xFF, 0xFE, 0, 2],
          plain.sublist(2),
        ])
      ),
      (
        'JPEG TEM markers',
        cat([
          soi,
          for (var i = 0; i < count; i++) [0xFF, 0x01],
          plain.sublist(2),
        ])
      ),
      (
        'PNG chunks',
        cat([
          png.sublist(0, 33),
          for (var i = 0; i < count; i++) pngChunk('tEXt', const []),
          png.sublist(33),
        ])
      ),
      (
        'WebP chunks',
        webp([for (var i = 0; i < count; i++) chunk('JUNK', const [])])
      ),
      (
        'HEIF boxes',
        cat([
          [0, 0, 0, 20, ...'ftypmif1'.codeUnits, 0, 0, 0, 0],
          'mif1'.codeUnits,
          for (var i = 0; i < count; i++) [0, 0, 0, 8, ...'free'.codeUnits],
        ])
      ),
    ]) {
      test('$label: a read per 64 kB', () async {
        var reads = 0;
        final inner = bytesReader(bytes);
        final watch = Stopwatch()..start();
        final blocks = await findExifBlocks((offset, length) {
          reads++;
          return inner(offset, length);
        });
        expect(blocks.cut, isFalse);
        expect(blocks.whole, isEmpty);
        expect(reads, lessThan(bytes.length / (64 << 10) + 10));
        expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      });
    }
  });

  group('the PNG walk', () {
    for (final (label, bytes) in [
      ('an eXIf before IDAT', png([pngChunk('eXIf', tiff)])),
      ('an eXIf after IDAT', png([], afterIdat: pngChunk('eXIf', tiff))),
    ]) {
      test('$label is found', () async {
        final blocks = await findExifBlocks(bytesReader(bytes));
        expect(blocks.cut, isFalse);
        expect(blocks.whole, [tiff]);
      });
    }

    test('an eXIf cut short counts as cut', () async {
      final bytes = png([], afterIdat: pngChunk('eXIf', tiff));
      final cut = bytes.sublist(0, bytes.length - 12 - 4 - 30);
      expect((await findExifBlocks(bytesReader(cut))).cut, isTrue);
    });
  });

  group('a WebP with its EXIF after an odd-sized chunk', () {
    test('with GPS: the location question, not the unreadable one', () async {
      final bytes = webp([oddImage, exifChunk]);
      expect(await readExifFromBytes(bytes), isEmpty,
          reason: 'the reader misses it');
      expect(await answer(bytes), LocationAnswer.found);
    });

    test('with the Exif\\0\\0 prefix some writers add: found too', () async {
      final bytes = webp([
        oddImage,
        chunk('EXIF', [...'Exif'.codeUnits, 0, 0, ...tiff])
      ]);
      expect(await answer(bytes), LocationAnswer.found);
    });

    test('the WebPs of the repository: no question', () async {
      var oddBeforeExif = 0;
      for (final path in [
        'assets/images/effects/particles/confetti.webp',
        'assets/images/effects/particles/fluent-emoji-eyes.webp',
        'assets/images/effects/particles/fluent-emoji-smile-with-hearts.webp',
        'assets/images/effects/particles/fluent-emoji-snowflake.webp',
        'assets/images/loading/rooster_vibing.webp',
      ]) {
        final bytes = File(path).readAsBytesSync();
        final blocks = await findExifBlocks(bytesReader(bytes));
        if (blocks.whole.isNotEmpty &&
            (await readExifFromBytes(bytes)).isEmpty) {
          oddBeforeExif++;
        }
        expect(await answer(bytes), LocationAnswer.none, reason: path);
      }
      expect(oddBeforeExif, 3,
          reason: 'three of them hold an EXIF the reader misses');
    });

    test('a RIFF size past the end of the file still counts as cut', () async {
      final bytes = webp([oddImage], riff: 4 + oddImage.length + 1000);
      expect((await findExifBlocks(bytesReader(bytes))).cut, isTrue);
      final lastWithoutPadding =
          webp([oddImage.sublist(0, oddImage.length - 1)], riff: 4 + 447);
      expect(await findExifBlocks(bytesReader(lastWithoutPadding)),
          isA<ExifBlocks>().having((b) => b.cut, 'cut', isFalse));
    });
  });

  group('a HEIF of a brand the Exif reader does not know', () {
    final mif1 = fixture('exif_mif1.heic');
    final heix = fixture('exif_heix.heic');
    final noGps = fixture('exif_no_gps.heic');

    test('the fixtures hold their Exif where a HEIF reader finds it', () async {
      for (final file in [mif1, heix]) {
        expect(await readerSeesGps(file), isFalse,
            reason: 'the reader does not know the brand');
        // Under the brand it knows, the Exif reader reads the same boxes.
        final asHeic = Uint8List.fromList(file)
          ..setRange(8, 12, 'heic'.codeUnits);
        expect(await readerSeesGps(asHeic), isTrue);
      }
    });

    for (final (brand, file) in [('mif1', mif1), ('heix', heix)]) {
      test('$brand with GPS: the location question', () async {
        expect(await answer(file), LocationAnswer.found);
      });

      test('$brand with its Exif cut short: the unreadable question', () async {
        final cut = file.sublist(0, file.length - 30);
        expect((await findExifBlocks(bytesReader(cut))).cut, isTrue);
        expect(await answer(cut), LocationAnswer.unreadable);
      });

      test('$brand with an Exif that does not read: the unreadable question',
          () async {
        final broken = Uint8List.fromList(file);
        final at = String.fromCharCodes(broken).indexOf('Exif\x00\x00MM');
        broken.setRange(at + 6, at + 8, 'XX'.codeUnits);
        expect(await answer(broken), LocationAnswer.unreadable);
      });
    }

    test('without GPS, 32-bit ids and a base offset: no question', () async {
      final blocks = await findExifBlocks(bytesReader(noGps));
      expect(blocks.whole, hasLength(1));
      expect(readExifOrientation(blocks.whole.single), 6);
      expect(await answer(noGps), LocationAnswer.none);
    });

    test('an ftyp of more than 4 kB: unreadable', () async {
      // mif1's own ftyp grown with 1,250 more brands.
      final ftypSize = 24 + 5000;
      final big = cat([
        [
          ftypSize >> 24,
          ftypSize >> 16 & 0xFF,
          ftypSize >> 8 & 0xFF,
          ftypSize & 0xFF
        ],
        Uint8List.sublistView(mif1, 4, 24),
        Uint8List(5000),
        Uint8List.sublistView(mif1, 24),
      ]);
      expect((await findExifBlocks(bytesReader(big))).cut, isTrue);
      expect(await answer(big), LocationAnswer.unreadable);
    });

    test('a video (no HEIF brand) is not walked', () async {
      final mp4 = Uint8List.fromList(mif1)..setRange(8, 12, 'isom'.codeUnits);
      mp4.setRange(16, 24, 'isomiso2'.codeUnits);
      expect((await findExifBlocks(bytesReader(mp4))).whole, isEmpty);
    });

    group('an iloc built to cost', () {
      List<int> be(int value, int size) =>
          [for (var i = size - 1; i >= 0; i--) value >> (8 * i) & 0xFF];
      List<int> box(String type, List<int> body) =>
          [...be(8 + body.length, 4), ...type.codeUnits, ...body];
      List<int> fullBox(String type, int version, List<int> body) =>
          box(type, [version, 0, 0, 0, ...body]);
      // A HEIF of brand mif1 whose meta holds an Exif item (id 1) and the
      // iloc [items] (version 1), followed by [after].
      Uint8List heif(List<int> items, {List<int> after = const []}) => cat([
            box('ftyp', [...'mif1'.codeUnits, 0, 0, 0, 0, ...'mif1'.codeUnits]),
            fullBox('meta', 0, [
              ...fullBox('iinf', 0, [
                ...be(1, 2),
                ...fullBox(
                    'infe', 2, [...be(1, 2), 0, 0, ...'Exif'.codeUnits, 0]),
              ]),
              ...fullBox('iloc', 1, items),
            ]),
            after,
          ]);

      test('extents of fields of size 0: unreadable, at once', () async {
        // The review's: 256 items of 65,535 extents that take no byte; and
        // the same with every item the Exif item (id 1), whose places are
        // kept.
        for (final exifEveryTime in [false, true]) {
          final bytes = heif([
            0x00, 0x00, // offset, length, base and index sizes: all 0
            ...be(256, 2),
            for (var n = 1; n <= 256; n++) ...[
              ...be(exifEveryTime ? 1 : n, 2),
              0,
              0,
              0,
              0,
              0xFF,
              0xFF
            ],
          ]);
          final watch = Stopwatch()..start();
          expect((await findExifBlocks(bytesReader(bytes))).cut, isTrue);
          expect(watch.elapsed, lessThan(const Duration(milliseconds: 200)),
              reason: 'the Exif item every time: $exifEveryTime');
          expect(await answer(bytes), LocationAnswer.unreadable);
        }
      });

      test('more extents or items than the box holds: unreadable', () async {
        for (final items in [
          [0x44, 0x00, ...be(1, 2), ...be(1, 2), 0, 0, 0, 0, ...be(1000, 2)],
          [0x44, 0x00, ...be(60000, 2), ...be(1, 2), 0, 0, 0, 0, ...be(1, 2)],
        ]) {
          expect((await findExifBlocks(bytesReader(heif(items)))).cut, isTrue);
        }
      });

      test('an Exif item of more than maxExifBlock in all: cut, not read',
          () async {
        // Two extents of 3 MB each, over the same bytes of the file.
        const length = 3 << 20;
        Uint8List build(int offset) => heif([
              0x44, 0x00, ...be(1, 2), // offset and length in 4 bytes, one item
              ...be(1, 2), 0, 0, 0, 0, ...be(2, 2),
              ...be(offset, 4), ...be(length, 4),
              ...be(offset, 4), ...be(length, 4),
            ], after: Uint8List(length));
        // The extents over the zeros at the end: a whole item, read twice.
        final bytes = build(build(0).length - length);
        final blocks = await findExifBlocks(bytesReader(bytes));
        expect(blocks.cut, isTrue);
        expect(blocks.whole, isEmpty);
      });
    });
  });

  group('a GPS pointer in the Exif sub-IFD', () {
    // IFD0 points to the Exif sub-IFD (0x8769) at [sub], which points to
    // the GPS IFD: some writers put the GPS pointer there, and the Exif
    // reader finds it.
    // With [interop], the sub-IFD points instead to an Interop IFD (0xA005)
    // that holds the GPS pointer.
    Uint8List subIfdGps(Endian endian,
        {int sub = 26, bool interop = false, int interopAt = 44}) {
      final d = ByteData(62)
        ..setUint16(0, endian == Endian.little ? 0x4949 : 0x4D4D)
        ..setUint16(2, 42, endian)
        ..setUint32(4, 8, endian);
      void ifd(int at, int tag, int value) => d
        ..setUint16(at, 1, endian)
        ..setUint16(at + 2, tag, endian)
        ..setUint16(at + 4, 4, endian) // LONG
        ..setUint32(at + 6, 1, endian)
        ..setUint32(at + 10, value, endian)
        ..setUint32(at + 14, 0, endian); // no next IFD
      ifd(8, 0x8769, sub);
      if (interop) {
        ifd(26, 0xA005, interopAt);
        ifd(44, 0x8825, 0);
        return d.buffer.asUint8List();
      }
      ifd(26, 0x8825, 44);
      d
        ..setUint16(44, 1, endian)
        ..setUint16(46, 0x0000, endian) // GPSVersionID
        ..setUint16(48, 1, endian) // BYTE
        ..setUint32(50, 4, endian)
        ..setUint8(54, 2)
        ..setUint8(55, 3);
      return d.buffer.asUint8List();
    }

    Uint8List exifSegment(Uint8List tiff) =>
        segment(0xE1, [...'Exif'.codeUnits, 0, 0, ...tiff]);

    for (final (name, endian) in [('II', Endian.little), ('MM', Endian.big)]) {
      test('$name, behind an APP2 of 5,000 bytes: the location question',
          () async {
        final app1 = exifSegment(subIfdGps(endian));
        expect(await readerSeesGps(cat([soi, app1, plain.sublist(2)])), isTrue,
            reason: 'the Exif reader finds it when nothing hides it');
        final hidden =
            cat([soi, segment(0xE2, Uint8List(4998)), app1, plain.sublist(2)]);
        expect(await readerSeesGps(hidden), isFalse);
        expect(await answer(hidden), LocationAnswer.found);
      });

      test(
          '$name, a sub-IFD pointer that is zero, points back or past the '
          'block: unreadable', () {
        expect(readExifGps(subIfdGps(endian)), ExifGps.found);
        for (final sub in [0, 8, 4, 4000]) {
          expect(readExifGps(subIfdGps(endian, sub: sub)), ExifGps.unreadable,
              reason: 'sub-IFD at $sub');
        }
      });

      test(
          '$name, a GPS pointer in the Interop IFD is found; a broken '
          'pointer to it is passed over', () {
        expect(readExifGps(subIfdGps(endian, interop: true)), ExifGps.found);
        for (final at in [0, 26, 4000]) {
          expect(readExifGps(subIfdGps(endian, interop: true, interopAt: at)),
              ExifGps.none,
              reason: 'Interop IFD at $at');
        }
      });
    }
  });

  group('readExifGps', () {
    // The minimal block in [endian] (IFD0: the orientation, or [ifd0Tag]),
    // its next-IFD offset pointing to an IFD1 of one entry, [entryTag].
    Uint8List withIfd1(int entryTag,
        {int? ifd1, Endian endian = Endian.big, int ifd0Tag = 0x0112}) {
      final out = ByteData(26 + 18)
        ..setUint16(0, endian == Endian.little ? 0x4949 : 0x4D4D)
        ..setUint16(2, 42, endian)
        ..setUint32(4, 8, endian)
        ..setUint16(8, 1, endian)
        ..setUint16(10, ifd0Tag, endian)
        ..setUint16(12, 3, endian)
        ..setUint32(14, 1, endian)
        ..setUint16(18, 1, endian)
        ..setUint32(22, ifd1 ?? 26, endian)
        ..setUint16(26, 1, endian)
        ..setUint16(28, entryTag, endian)
        ..setUint16(30, 4, endian)
        ..setUint32(32, 1, endian);
      return out.buffer.asUint8List();
    }

    test('a GPS pointer in IFD0 or IFD1 is found', () {
      expect(readExifGps(tiff), ExifGps.found);
      expect(readExifGps(withIfd1(0x8825)), ExifGps.found);
      expect(readExifGps(withIfd1(0x0100)), ExifGps.none);
      expect(readExifGps(minimalOrientationTiff(6)), ExifGps.none);
    });

    test('a little-endian (II) block, as Android writes them, reads the same',
        () {
      const ii = Endian.little;
      expect(readExifGps(withIfd1(0x0100, endian: ii, ifd0Tag: 0x8825)),
          ExifGps.found,
          reason: 'GPS in IFD0');
      expect(readExifGps(withIfd1(0x8825, endian: ii)), ExifGps.found);
      expect(readExifGps(withIfd1(0x0100, endian: ii)), ExifGps.none);
      expect(
          readExifGps(withIfd1(0x8825, endian: ii, ifd1: 4000)), ExifGps.none);
    });

    test('an IFD0 that does not fit is unreadable; a later IFD ends there', () {
      expect(
          readExifGps(Uint8List.sublistView(tiff, 0, 20)), ExifGps.unreadable);
      expect(readExifGps(Uint8List(4)), ExifGps.unreadable);
      expect(readExifGps(Uint8List.fromList(tiff)..[0] = 0x58),
          ExifGps.unreadable);
      expect(readExifGps(withIfd1(0x8825, ifd1: 4000)), ExifGps.none);
    });
  });
}
