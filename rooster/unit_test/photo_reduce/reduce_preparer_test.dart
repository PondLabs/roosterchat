import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/utils/image/image_header.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:rooster/utils/image/preparation/thumbnail_encoder.dart';

import '../media_prepare/fakes.dart';

/// Records what it is asked and answers with a reduced photo when asked.
class _ReducingEncoder implements ThumbnailEncoder {
  final List<ThumbnailRequest> requests = [];

  @override
  Future<ThumbnailResult> encode(ThumbnailRequest request) async {
    requests.add(request);
    final reduceTo = request.reduceTo;
    ReducedPhoto? reduced;
    if (reduceTo != null) {
      final (w, h) = fitWithin(request.width, request.height, reduceTo);
      reduced = ReducedPhoto(bytes: Uint8List(1234), width: w, height: h);
    }
    return ThumbnailResult(blurhash: "LKO2?U%2Tw=w", reduced: reduced);
  }
}

/// Which pictures are reduced, and that the one decode is then at the
/// reduced size: the engine and the encoder are fakes here (the real ones
/// are in `reduce_send_test.dart`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ImagePreparation?, FakeEngine, _ReducingEncoder, SpeedLog)> prepare(
      Uint8List bytes,
      {required int width,
      required int height,
      bool reduce = true}) async {
    final engine = FakeEngine(width: width, height: height);
    final encoder = _ReducingEncoder();
    final log = SpeedLog(frames: NoFrames());
    final preparer =
        ImagePreparer(codecFactory: engine.codec, encoder: encoder, log: log);
    final prepared = await preparer.prepare(bytes, reduce: reduce);
    return (prepared, engine, encoder, log);
  }

  test("photoReducedSize: only a JPEG over 2,560 px, as displayed", () {
    ImageHeader jpeg(int w, int h, [int orientation = 1]) => ImageHeader(
        mimeType: "image/jpeg",
        storedWidth: w,
        storedHeight: h,
        orientation: orientation);
    expect(photoReducedSize(jpeg(4032, 3024)), (2560, 1920));
    expect(photoReducedSize(jpeg(4032, 3024, 6)), (1920, 2560));
    expect(photoReducedSize(jpeg(3024, 4032, 8)), (2560, 1920));
    expect(photoReducedSize(jpeg(2560, 1920)), isNull);
    expect(photoReducedSize(jpeg(2000, 1500)), isNull);
    for (final mime in ["image/png", "image/webp", "image/gif", "image/bmp"]) {
      expect(
          photoReducedSize(ImageHeader(
              mimeType: mime, storedWidth: 3840, storedHeight: 2160)),
          isNull,
          reason: mime);
    }
  });

  test("a JPEG over 2,560 px: one decode at 2,560, the photo asked for",
      () async {
    final (prepared, engine, encoder, log) =
        await prepare(fakeJpegHeader(4032, 3024), width: 4032, height: 3024);
    expect(engine.calls.map((c) => (c.targetWidth, c.targetHeight)),
        [(2560, 1920)]);
    expect(encoder.requests.single.reduceTo, photoMaxSide);
    expect(encoder.requests.single.maxSide, thumbnailMaxSide);
    expect((encoder.requests.single.width, encoder.requests.single.height),
        (2560, 1920));
    final reduced = prepared!.reduced!;
    expect((reduced.width, reduced.height), (2560, 1920));
    // The preparation's own size stays the attached picture's.
    expect((prepared.width, prepared.height), (4032, 3024));

    final steps = log.spans.toList().single.steps;
    expect(steps.map((s) => s.name), contains(SpeedStep.reduce));
    expect(steps.map((s) => s.name), isNot(contains(SpeedStep.encode)));
    expect(steps.firstWhere((s) => s.name == SpeedStep.reduce).values, {
      SpeedValue.bytes: 1234,
      SpeedValue.width: 2560,
      SpeedValue.height: 1920,
    });
  });

  test("a portrait photo (orientation 6) is decoded at 2,560 high", () async {
    final (prepared, engine, encoder, _) = await prepare(
        fakeJpegHeader(4032, 3024, orientation: 6),
        width: 3024,
        height: 4032);
    expect(engine.calls.map((c) => (c.targetWidth, c.targetHeight)),
        [(1920, 2560)]);
    expect((prepared!.reduced!.width, prepared.reduced!.height), (1920, 2560));
  });

  test("without reduce (\"Send original\"), the decode is the thumbnail's",
      () async {
    final (prepared, engine, encoder, log) = await prepare(
        fakeJpegHeader(4032, 3024),
        width: 4032,
        height: 3024,
        reduce: false);
    expect(engine.calls.map((c) => (c.targetWidth, c.targetHeight)),
        [(800, null)]);
    expect(encoder.requests.single.reduceTo, isNull);
    expect(prepared!.reduced, isNull);
    expect(log.spans.toList().single.steps.map((s) => s.name),
        isNot(contains(SpeedStep.reduce)));
  });

  test("a JPEG of 2,560 px or less is not reduced", () async {
    for (final (w, h) in [(2560, 1920), (2000, 1500)]) {
      final (prepared, engine, encoder, _) =
          await prepare(fakeJpegHeader(w, h), width: w, height: h);
      expect(engine.calls.single.targetWidth, 800, reason: "$w x $h");
      expect(encoder.requests.single.reduceTo, isNull);
      expect(prepared!.reduced, isNull);
    }
  });

  test("a PNG of 3,840 x 2,160 is not reduced", () async {
    // An IHDR with the size, padded: enough for the header reader.
    final png = Uint8List(400 * 1000)
      ..setAll(0, [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, //
        0, 0, 0x0F, 0x00, 0, 0, 0x08, 0x70, 8, 6, 0, 0, 0,
      ]);
    expect(readImageHeader(png)!.width, 3840);
    final (prepared, engine, encoder, _) =
        await prepare(png, width: 3840, height: 2160);
    expect(engine.calls.single.targetWidth, 800);
    expect(encoder.requests.single.reduceTo, isNull);
    expect(prepared!.reduced, isNull);
  });
}
