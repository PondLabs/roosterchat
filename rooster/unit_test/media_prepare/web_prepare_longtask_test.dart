import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/image/image_header.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import 'browser_probe.dart'
    if (dart.library.js_interop) 'browser_probe_web.dart';
import 'fakes.dart';

/// The web path: a 4032 x 3024 photo drawn in a canvas is prepared (one
/// engine decode at 800 px, the thumbnail by the browser's canvas) while a
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

  test("a 4032 x 3024 photo is prepared with no main-thread task over 100 ms",
      skip: skip, () async {
    final bytes = await canvasPhotoJpeg(4032, 3024);
    expect(readImageHeader(bytes)!.width, 4032);
    expect(bytes.length, greaterThanOrEqualTo(thumbnailMinSourceBytes));
    final log = SpeedLog(frames: NoFrames());
    final preparer = ImagePreparer(log: log);

    // Settle anything the canvas left behind before watching.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final observer = LongTaskObserver.start();
    final watch = Stopwatch()..start();
    final prepared = await preparer.prepare(bytes);
    watch.stop();
    final tasks = await observer.stop();

    final thumbnail = prepared!.thumbnail!;
    final steps = log.spans.toList().single.steps;
    // ignore: avoid_print
    print("steps: ${steps.map((s) => "${s.name} "
        "${s.duration!.inMicroseconds / 1000} ms ${s.values}").join("; ")}");
    // ignore: avoid_print
    print("web: ${bytes.length} bytes prepared in ${watch.elapsedMilliseconds}"
        " ms; ${prepared.width} x ${prepared.height}, thumbnail "
        "${thumbnail.mimeType} ${thumbnail.width} x ${thumbnail.height} "
        "${thumbnail.bytes.length} bytes; long tasks "
        "${tasks.map((t) => t.round()).toList()} ms");
    expect((prepared.width, prepared.height), (4032, 3024));
    expect(thumbnail.mimeType, "image/jpeg");
    expect((thumbnail.width, thumbnail.height), (800, 600));
    expect(readImageHeader(thumbnail.bytes)!.mimeType, "image/jpeg");
    expect(prepared.blurhash, isNotNull);
    expect(tasks.where((t) => t > 100), isEmpty,
        reason: "long tasks (ms): $tasks");
  });

  test("a PNG with transparency gets a PNG thumbnail from the canvas too",
      skip: skip, () async {
    final bytes = await canvasTransparentPng(1600, 1200);
    expect(bytes.length, greaterThanOrEqualTo(thumbnailMinSourceBytes));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final observer = LongTaskObserver.start();
    final prepared =
        await ImagePreparer(log: SpeedLog(frames: NoFrames())).prepare(bytes);
    final tasks = await observer.stop();
    final thumbnail = prepared!.thumbnail!;
    // ignore: avoid_print
    print("web PNG: ${bytes.length} bytes; thumbnail ${thumbnail.mimeType} "
        "${thumbnail.width} x ${thumbnail.height} "
        "${thumbnail.bytes.length} bytes; long tasks "
        "${tasks.map((t) => t.round()).toList()} ms");
    expect(thumbnail.mimeType, "image/png");
    expect(readImageHeader(thumbnail.bytes)!.mimeType, "image/png");
    expect((thumbnail.width, thumbnail.height), (800, 600));
    expect(tasks.where((t) => t > 100), isEmpty,
        reason: "long tasks (ms): $tasks");
  });
}
