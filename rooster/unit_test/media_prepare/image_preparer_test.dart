import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import 'fakes.dart';

/// The preparer's own logic, with the engine and the encoder replaced:
/// how it decodes, how many at once, what it disposes.
void main() {
  test("ten pictures attached at once: at most two are prepared at a time",
      () async {
    final waiting = <Completer<void>>[];
    final engine = FakeEngine(gate: () {
      final turn = Completer<void>();
      waiting.add(turn);
      return turn.future;
    });
    final preparer = fakePreparer(engine);

    final results =
        List.generate(10, (_) => preparer.prepare(fakeJpegHeader(4032, 3024)));
    var peak = 0;
    var released = 0;
    while (released < 10) {
      await pumpEventQueue();
      expect(preparer.running, lessThanOrEqualTo(2));
      expect(waiting.length - released, lessThanOrEqualTo(2));
      if (preparer.running > peak) peak = preparer.running;
      waiting[released++].complete();
    }
    final prepared = await Future.wait(results);
    expect(prepared, everyElement(isNotNull));
    expect(peak, 2, reason: "two run side by side, not one");
    expect(engine.peakOpen, lessThanOrEqualTo(2));
    expect(engine.calls, hasLength(10));
    expect(preparer.running, 0);
  });

  test("every codec and image created is disposed exactly once", () async {
    for (final engine in [
      FakeEngine(),
      FakeEngine(frames: 4),
      FakeEngine(failPixels: true),
    ]) {
      final preparer = fakePreparer(engine);
      await preparer.prepare(fakeJpegHeader(4032, 3024));
      await preparer.prepare(fakeJpegHeader(640, 480, length: 1000));
      expect(engine.codecs, hasLength(engine.calls.length));
      expect(engine.images, hasLength(engine.codecs.length));
      for (final codec in engine.codecs) {
        expect(codec.disposed, 1);
      }
      for (final image in engine.images) {
        expect(image.disposed, 1);
      }
    }
  });

  test("a large photo is decoded once, at thumbnail size, on its long side",
      () async {
    final engine = FakeEngine(width: 4032, height: 3024);
    final encoder = FakeEncoder();
    final prepared = await fakePreparer(engine, encoder: encoder)
        .prepare(fakeJpegHeader(4032, 3024));

    expect(engine.calls, hasLength(1));
    expect(engine.calls.single.targetWidth, 800);
    expect(engine.calls.single.targetHeight, isNull);
    expect(encoder.requests.single.width, 800);
    expect(encoder.requests.single.height, 600);
    expect(encoder.requests.single.maxSide, 800);
    expect(encoder.requests.single.mayHaveAlpha, isFalse, reason: "a JPEG");
    expect(prepared!.width, 4032);
    expect(prepared.height, 3024);
    expect(prepared.mimeType, "image/jpeg");
    expect(prepared.thumbnail!.width, 800);
    expect(prepared.thumbnail!.height, 600);
    expect(prepared.blurhash, isNotNull);
  });

  test("orientation 6: the sides are swapped, as the engine draws it",
      () async {
    // The engine draws the stored 4032 x 3024 turned: 3024 x 4032.
    final engine = FakeEngine(width: 3024, height: 4032);
    final prepared = await fakePreparer(engine)
        .prepare(fakeJpegHeader(4032, 3024, orientation: 6));

    expect(engine.calls.single.targetHeight, 800);
    expect(engine.calls.single.targetWidth, isNull);
    expect(prepared!.width, 3024);
    expect(prepared.height, 4032);
    expect(prepared.thumbnail!.width, 600);
    expect(prepared.thumbnail!.height, 800);
  });

  test("a tag the engine does not apply: the engine's drawing wins", () async {
    // The header says orientation 6, the engine draws it as stored (as
    // with a WebP whose EXIF has the Exif\0\0 prefix).
    final engine = FakeEngine(width: 4032, height: 3024);
    final encoder = FakeEncoder();
    final prepared = await fakePreparer(engine, encoder: encoder)
        .prepare(fakeJpegHeader(4032, 3024, orientation: 6));

    expect(prepared!.width, 4032);
    expect(prepared.height, 3024);
    // Asked for 800 on what it thought was the long side, the engine gave
    // 1067 x 800; the thumbnail still fits in 800.
    expect(prepared.thumbnail!.width, 800);
    expect(prepared.thumbnail!.height, 600);
  });

  test("a small source gets no thumbnail and a decode only for the blurhash",
      () async {
    for (final (label, bytes, w, h) in [
      ("800 px", fakeJpegHeader(800, 533), 800, 533),
      (
        "under 300 kB",
        fakeJpegHeader(4032, 3024, length: 299 * 1000),
        4032,
        3024
      ),
    ]) {
      final engine = FakeEngine(width: w, height: h);
      final encoder = FakeEncoder();
      final prepared =
          await fakePreparer(engine, encoder: encoder).prepare(bytes);
      expect(engine.calls.single.targetWidth, 64, reason: label);
      expect(encoder.requests.single.maxSide, isNull, reason: label);
      expect(prepared!.thumbnail, isNull, reason: label);
      expect(prepared.blurhash, isNotNull, reason: label);
      expect((prepared.width, prepared.height), (w, h), reason: label);
    }
  });

  test("an animation gets no thumbnail, so the timeline plays it", () async {
    final engine = FakeEngine(width: 4032, height: 3024, frames: 12);
    final encoder = FakeEncoder();
    final prepared = await fakePreparer(engine, encoder: encoder)
        .prepare(fakeJpegHeader(4032, 3024));
    expect(prepared!.animated, isTrue);
    expect(prepared.thumbnail, isNull);
    expect(encoder.requests.single.maxSide, isNull);
  });

  test("a file the engine cannot decode prepares to null, and says so",
      () async {
    final log = SpeedLog(frames: NoFrames());
    final preparer = ImagePreparer(
      codecFactory: (bytes, {targetWidth, targetHeight}) =>
          Future.error(Exception("not a picture")),
      encoder: FakeEncoder(),
      log: log,
    );
    expect(await preparer.prepare(fakeJpegHeader(4032, 3024)), isNull);
    expect(preparer.running, 0);
    expect(log.spans.toList().single.outcome, "failed");
  });

  test("each preparation is a span with its steps and sizes", () async {
    final log = SpeedLog(frames: NoFrames());
    await fakePreparer(FakeEngine(width: 4032, height: 3024), log: log)
        .prepare(fakeJpegHeader(4032, 3024));
    final span = log.spans.toList().single;
    expect(span.name, "image_prepare");
    expect(span.outcome, "ok");
    expect(span.steps.map((s) => s.name),
        ["queue_wait", "header", "decode", "encode"]);
    expect(span.steps[1].values, {"bytes": 400 * 1000});
    expect(span.steps[2].values, {"width": 800, "height": 600, "frames": 1});
    expect(span.steps[3].values, {"bytes": 10, "width": 800, "height": 600});
  });
}
