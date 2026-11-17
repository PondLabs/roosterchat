import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/utils/image/image_header.dart';
import 'package:rooster/utils/image/metadata/image_container.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/browser_probe.dart'
    if (dart.library.js_interop) '../media_prepare/browser_probe_web.dart';
import '../media_prepare/fakes.dart';

/// The web path of a reduced photo: a 4032 x 3024 photo drawn in a canvas
/// is decoded once by the engine at 2,560 px, and the browser's canvas
/// encodes the reduced photo and its thumbnail, while a
/// `PerformanceObserver` watches for long tasks on the main thread.
///
/// Browser only (the VM run skips it): see "Teste em Chrome" in the
/// project notes for the command.
void main() {
  const skip = kIsWeb ? null : "browser only: run with --platform chrome";

  test("the long-task observer sees a 150 ms task (control)", skip: skip,
      () async {
    final observer = LongTaskObserver.start();
    busyFor(const Duration(milliseconds: 150));
    final tasks = await observer.stop();
    // ignore: avoid_print
    print("control: long tasks ${tasks.map((t) => t.round()).toList()} ms");
    expect(tasks.any((t) => t >= 140), isTrue,
        reason: "otherwise the observer below proves nothing");
  });

  test("a 4032 x 3024 photo is reduced with no main-thread task over 100 ms",
      skip: skip, () async {
    final bytes = await canvasPhotoJpeg(4032, 3024);
    expect(readImageHeader(bytes)!.width, 4032);
    final log = SpeedLog(frames: NoFrames());
    final preparer = ImagePreparer(log: log);

    // Settle anything the canvas left behind before watching.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final observer = LongTaskObserver.start();
    final watch = Stopwatch()..start();
    final prepared = await preparer.prepare(bytes, reduce: true);
    watch.stop();
    final tasks = await observer.stop();

    final reduced = prepared!.reduced!;
    final thumbnail = prepared.thumbnail!;
    final steps = log.spans.toList().single.steps;
    // ignore: avoid_print
    print("steps: ${steps.map((s) => "${s.name} "
        "${s.duration!.inMicroseconds / 1000} ms ${s.values}").join("; ")}");
    // ignore: avoid_print
    print("web: ${bytes.length} bytes reduced in ${watch.elapsedMilliseconds}"
        " ms to ${reduced.width} x ${reduced.height}, "
        "${reduced.bytes.length} bytes; thumbnail ${thumbnail.width} x "
        "${thumbnail.height}; long tasks "
        "${tasks.map((t) => t.round()).toList()} ms");

    expect(steps.map((s) => s.name), contains(SpeedStep.reduce));
    expect((reduced.width, reduced.height), (2560, 1920));
    final header = readImageHeader(reduced.bytes)!;
    expect(header.mimeType, "image/jpeg");
    expect((header.width, header.height), (2560, 1920));
    expect(header.orientation, 1);
    expect(parseImageContainer(reduced.bytes)!.withoutMetadata(), reduced.bytes,
        reason: "nothing left for the metadata allowlist to remove");
    expect(reduced.bytes.length, lessThan(bytes.length));
    expect((thumbnail.width, thumbnail.height), (800, 600));
    expect(prepared.blurhash, isNotNull);
    expect(tasks.where((t) => t > 100), isEmpty,
        reason: "long tasks (ms): $tasks");
  });

  test("a 3:2 photo lying down: the size the dialog says", skip: skip,
      () async {
    final bytes = await canvasPhotoJpeg(3000, 2000);
    final said = photoReducedSize(readImageHeader(bytes)!);
    expect(said, (2560, 1707));
    final prepared = await ImagePreparer(log: SpeedLog(frames: NoFrames()))
        .prepare(bytes, reduce: true);
    final reduced = prepared!.reduced!;
    final header = readImageHeader(reduced.bytes)!;
    expect((reduced.width, reduced.height), said);
    expect((header.width, header.height), said);
  });
}
