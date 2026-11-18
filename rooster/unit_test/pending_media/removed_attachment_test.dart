import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';

/// An attachment removed from the composer before Send leaves the
/// preparation queue: it is not prepared, or what it had prepared is
/// thrown away.
void main() {
  late List<Completer<void>> gates;
  late FakeEngine engine;
  late SpeedLog log;
  late ImagePreparer preparer;

  setUp(() {
    gates = [];
    engine = FakeEngine(gate: () {
      final turn = Completer<void>();
      gates.add(turn);
      return turn.future;
    });
    log = SpeedLog(frames: NoFrames());
    preparer = fakePreparer(engine, log: log);
  });

  /// Lets every decode waiting on its gate go on, until none is left.
  Future<void> drain() async {
    var released = 0;
    while (true) {
      await pumpEventQueue();
      if (released == gates.length) break;
      while (released < gates.length) {
        final gate = gates[released++];
        if (!gate.isCompleted) gate.complete();
      }
    }
  }

  test(
      'ten pictures attached, five removed: the queued ones are never '
      'decoded, the running one is thrown away, the five kept are prepared',
      () async {
    final attachments = [
      for (var i = 0; i < 10; i++)
        PendingFileAttachment(
            name: 'p$i.jpg', data: fakeJpegHeader(4032, 3024 + i))
    ];
    final started = [
      for (final a in attachments) a.startImagePreparation(preparer: preparer)
    ];
    await pumpEventQueue();
    // The first two are decoding, the other eight wait their turn.
    expect(engine.calls, hasLength(2));
    expect(preparer.running, 2);

    // Removed: one that is decoding (1) and four still in the queue.
    final removed = [1, 3, 5, 7, 9];
    for (final i in removed) {
      attachments[i].discard();
    }

    await drain();
    await Future.wait(started);

    // Decoded: the two that had started, and the five kept that waited.
    final decoded = engine.calls.map((c) => c.bytes).toSet();
    for (final i in removed.skip(1)) {
      expect(decoded.contains(attachments[i].data), isFalse,
          reason: 'p$i left the queue before its turn');
    }
    expect(engine.calls, hasLength(6));
    // Every codec and image created was disposed once, the thrown away
    // one's too.
    expect(engine.codecs, hasLength(6));
    expect(engine.images, hasLength(6));
    for (final codec in engine.codecs) {
      expect(codec.disposed, 1);
    }
    for (final image in engine.images) {
      expect(image.disposed, 1);
    }
    expect(preparer.running, 0);

    for (final i in removed) {
      expect(await attachments[i].imagePreparation(preparer: preparer), isNull,
          reason: 'p$i was discarded');
    }
    for (final i in [0, 2, 4, 6, 8]) {
      final prepared =
          await attachments[i].imagePreparation(preparer: preparer);
      expect(prepared, isNotNull, reason: 'p$i was kept');
      expect(prepared!.height, 3024 + i);
    }
    // Nothing more was decoded to answer those questions.
    expect(engine.calls, hasLength(6));

    final outcomes = [
      for (final span in log.spans.toList())
        if (span.name == SpeedOperation.imagePrepare) span.outcome
    ];
    expect(outcomes.where((o) => o == SpeedOutcome.cancelled), hasLength(5));
    expect(outcomes.where((o) => o == SpeedOutcome.ok), hasLength(5));
  });

  test('a discarded attachment frees its place for the next one at once',
      () async {
    final a =
        PendingFileAttachment(name: 'a.jpg', data: fakeJpegHeader(4032, 3024));
    final b =
        PendingFileAttachment(name: 'b.jpg', data: fakeJpegHeader(4032, 3024));
    final c =
        PendingFileAttachment(name: 'c.jpg', data: fakeJpegHeader(4032, 3024));
    final d =
        PendingFileAttachment(name: 'd.jpg', data: fakeJpegHeader(4032, 3024));
    for (final x in [a, b, c, d]) {
      unawaited(x.startImagePreparation(preparer: preparer));
    }
    await pumpEventQueue();
    expect(engine.calls.map((x) => x.bytes), [a.data, b.data]);

    c.discard();
    // a's decode finishes: the slot goes to d, c is skipped.
    gates[0].complete();
    await pumpEventQueue();
    expect(engine.calls.map((x) => x.bytes), [a.data, b.data, d.data]);
    await drain();
  });
}
