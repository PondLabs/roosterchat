import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/image/image_header.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:rooster/utils/image/preparation/thumbnail_encoder.dart';

import 'fakes.dart';
import 'pictures.dart';

/// Attaching files the preparation must leave alone or survive.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync("t22_attach"));
  tearDown(() => dir.deleteSync(recursive: true));

  ImagePreparer preparer() =>
      ImagePreparer(encoder: FakeEncoder(), log: SpeedLog(frames: NoFrames()));

  test("a file that is not a picture is not read when it is attached",
      () async {
    final file = File("${dir.path}/clip.mp4")
      ..writeAsBytesSync(Uint8List(2 * 1000 * 1000));
    final attachment = PendingFileAttachment(
        name: "clip.mp4", path: file.path, size: 2 * 1000 * 1000);
    expect(attachment.mimeType, "video/mp4");

    await attachment.startImagePreparation(preparer: preparer());
    expect(attachment.data, isNull, reason: "read at Send, as before");

    await attachment.resolve(); // what Send does
    expect(attachment.data, hasLength(2 * 1000 * 1000));
  });

  test("a picture that cannot be read when attached: no error, Send reads it",
      () async {
    final bytes = File("unit_test/fixtures/image_metadata/orientation_6.jpg")
        .readAsBytesSync();
    // A file whose read fails, made by the test rather than by the system
    // (a lock does not stop a read on Linux or macOS), so the read fails
    // the same way on all three.
    final files = _Files({"/photos/photo.jpg": bytes})..failing = true;
    await IOOverrides.runZoned(() async {
      final attachment =
          PendingFileAttachment(name: "photo.jpg", path: "/photos/photo.jpg");

      // chat.dart does not wait for this future: it must not end in error.
      await expectLater(
          attachment.startImagePreparation(preparer: preparer()), completes);
      expect(files.reads, 1, reason: "the read was tried, and failed");
      expect(attachment.data, isNull);

      files.failing = false;
      await attachment.resolve(); // Send, once the file can be read
      expect(files.reads, 2);
      final prepared = await attachment.imagePreparation(preparer: preparer());
      expect((prepared!.width, prepared.height), (48, 64));
    }, createFile: files.create);
  });

  test(
      "Send pressed while the attached file is still being read: one read, "
      "one decode", () async {
    final gate = Completer<void>();
    final files = _Files({"/photos/big.jpg": fakeJpegHeader(4000, 3000)})
      ..gate = gate.future;
    final engine = FakeEngine(width: 4000, height: 3000);
    final preparer = fakePreparer(engine);
    await IOOverrides.runZoned(() async {
      final attachment =
          PendingFileAttachment(name: "big.jpg", path: "/photos/big.jpg");
      // Attached: the read starts, and takes its time.
      final attached = attachment.startImagePreparation(preparer: preparer);
      await pumpEventQueue();
      expect(files.reads, 1);

      // Send, while the read is still going.
      final sent = matrixFilesForAttachment(attachment, preparer: preparer);
      await pumpEventQueue();
      gate.complete();
      await attached;
      final processed = (await sent)!;

      expect(files.reads, 1, reason: "read once");
      expect(engine.calls, hasLength(1), reason: "decoded once");
      expect(identical(processed.file.bytes, attachment.data), isTrue);
      expect(
          (processed.file.info["w"], processed.file.info["h"]), (4000, 3000));
    }, createFile: files.create);
  });

  test(
      "a BMP from attach to Send: one decode, at full size, and the event "
      "goes as the PNG made from it", () async {
    final bmp = _screenshotBmp();
    final decodes = <(int?, int?)>[];
    final preparer = ImagePreparer(
        codecFactory: (bytes, {targetWidth, targetHeight}) {
          decodes.add((targetWidth, targetHeight));
          return engineImageCodec(bytes,
              targetWidth: targetWidth, targetHeight: targetHeight);
        },
        log: SpeedLog(frames: NoFrames()));
    final attachment =
        PendingFileAttachment(name: "shot.bmp", data: bmp, size: bmp.length);
    expect(attachment.mimeType, "image/bmp");

    await attachment.startImagePreparation(preparer: preparer); // attached
    final prepared = (await attachment.imagePreparation(preparer: preparer))!;
    final processed =
        (await matrixFilesForAttachment(attachment, preparer: preparer))!;

    expect(decodes, [(null, null)], reason: "one decode, at full size");
    expect(processed.file.mimeType, "image/png");
    expect(processed.file.name, "shot.bmp");
    expect(identical(processed.file.bytes, prepared.png), isTrue,
        reason: "the PNG the preparation made");
    expect(processed.file.bytes.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    expect((processed.file.info["w"], processed.file.info["h"]), (1600, 1000));
    final png = img.decodePng(processed.file.bytes)!;
    expect((png.width, png.height), (1600, 1000));
    expect(png.getPixel(100, 50).r, 40, reason: "the first bar");
  });

  test(
      "a BMP whose header the header reader does not know (16 bytes, "
      "OS/2 2.x) is still sent as a PNG, from its one decode", () async {
    final bmp = _os2Bmp(40, 30);
    expect(readImageHeader(bmp), isNull);
    var decodes = 0;
    final preparer = ImagePreparer(
        codecFactory: (bytes, {targetWidth, targetHeight}) {
          decodes++;
          return engineImageCodec(bytes,
              targetWidth: targetWidth, targetHeight: targetHeight);
        },
        log: SpeedLog(frames: NoFrames()));
    final attachment =
        PendingFileAttachment(name: "old.bmp", data: bmp, size: bmp.length);
    expect(attachment.mimeType, "image/bmp");

    final prepared = (await attachment.imagePreparation(preparer: preparer))!;
    final processed =
        (await matrixFilesForAttachment(attachment, preparer: preparer))!;

    expect(decodes, 1);
    expect(processed.file.mimeType, "image/png");
    expect(identical(processed.file.bytes, prepared.png), isTrue);
    final png = img.decodePng(processed.file.bytes)!;
    expect((png.width, png.height), (40, 30));
    expect((processed.file.info["w"], processed.file.info["h"]), (40, 30));
    expect(png.getPixel(3, 0).r, 200, reason: "the top row, red");
  });

  test("a thumbnail no smaller than the file sent is left out", () async {
    // A flat screenshot: 4.8 MB as BMP, a few kB once sent as PNG.
    final bmp = _screenshotBmp();
    final attachment =
        PendingFileAttachment(name: "shot.bmp", data: bmp, size: bmp.length);
    final processed = (await matrixFilesForAttachment(attachment,
        preparer: ImagePreparer(log: SpeedLog(frames: NoFrames()))))!;

    expect(processed.file.mimeType, "image/png");
    expect(processed.thumbnailFile, isNull,
        reason: "the PNG is ${processed.file.bytes.length} bytes");
    expect(processed.file, isA<PreparedImageFile>(),
        reason: "an m.image the SDK makes no thumbnail for");
    expect((processed.file.info["w"], processed.file.info["h"]), (1600, 1000));
  });

  test("the thumbnail encoder failing: still a picture, without a thumbnail",
      () async {
    final jpeg = largeJpegWithExifOf(
        File("unit_test/fixtures/image_metadata/orientation_6.jpg")
            .readAsBytesSync());
    final attachment =
        PendingFileAttachment(name: "p.jpg", data: jpeg, size: jpeg.length);
    final processed = (await matrixFilesForAttachment(attachment,
        preparer: ImagePreparer(
            encoder: _FailingEncoder(), log: SpeedLog(frames: NoFrames()))))!;

    expect(processed.file.msgType, "m.image");
    expect(processed.file.mimeType, "image/jpeg");
    expect(processed.thumbnailFile, isNull);
    expect((processed.file.info["w"], processed.file.info["h"]), (1500, 2000));
  });
}

class _FailingEncoder implements ThumbnailEncoder {
  @override
  Future<ThumbnailResult> encode(ThumbnailRequest request) =>
      Future.error(StateError("encoder unavailable"));
}

/// A 24-bit BMP with the 16-byte OS/2 2.x info header (width, height,
/// planes, bits), bottom-up: the top row red, the rest grey.
Uint8List _os2Bmp(int width, int height) {
  final rowSize = (width * 3 + 3) & ~3;
  const offset = 14 + 16;
  final out = ByteData(offset + rowSize * height)
    ..setUint8(0, 0x42) // B
    ..setUint8(1, 0x4D) // M
    ..setUint32(2, offset + rowSize * height, Endian.little)
    ..setUint32(10, offset, Endian.little)
    ..setUint32(14, 16, Endian.little) // info header size
    ..setUint32(18, width, Endian.little)
    ..setUint32(22, height, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little);
  for (var y = 0; y < height; y++) {
    final row = offset + (height - 1 - y) * rowSize;
    for (var x = 0; x < width; x++) {
      final top = y == 0;
      out
        ..setUint8(row + x * 3, top ? 0 : 128) // B
        ..setUint8(row + x * 3 + 1, top ? 0 : 128) // G
        ..setUint8(row + x * 3 + 2, top ? 200 : 128); // R
    }
  }
  return out.buffer.asUint8List();
}

/// A flat screenshot, 1600 by 1000: 4.8 MB as BMP, a few kB as PNG.
Uint8List _screenshotBmp() {
  final picture = img.Image(width: 1600, height: 1000);
  img.fill(picture, color: img.ColorRgb8(245, 245, 245));
  for (var i = 0; i < 12; i++) {
    img.fillRect(picture,
        x1: 60,
        y1: 40 + i * 70,
        x2: 900 + i * 40,
        y2: 70 + i * 70,
        color: img.ColorRgb8(40, 40, 60));
  }
  return img.encodeBmp(picture);
}

/// Files that live in the test: [create] makes a [File] for a path in
/// [contents], whose read throws while [failing] and waits for [gate] when
/// it is set. [reads] counts the reads tried.
class _Files {
  _Files(this.contents);

  final Map<String, Uint8List> contents;
  bool failing = false;
  Future<void>? gate;
  int reads = 0;

  File create(String path) => _File(this, path);
}

class _File implements File {
  _File(this._files, this.path);

  final _Files _files;

  @override
  final String path;

  @override
  Future<bool> exists() async => _files.contents.containsKey(path);

  @override
  Future<Uint8List> readAsBytes() async {
    _files.reads++;
    await _files.gate;
    if (_files.failing) {
      throw FileSystemException("Cannot read", path);
    }
    // A new list for every read, as a real file gives.
    return Uint8List.fromList(_files.contents[path]!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
