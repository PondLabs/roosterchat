import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/image/metadata/remove_image_metadata.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import 'photos.dart';

/// How long the native path takes to reduce the 12 MP photo, from the
/// attach dialog's output to the reduced JPEG (one engine decode at
/// 2,560, the encode in a background isolate): the time Send can wait for
/// the preparation. Prints the time and the steps; run three times for a
/// measurement (see "Como medir" in the project notes).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("the 12 MP photo is reduced in the time printed",
      skip: sampleDir == null
          ? "set SPEED_SAMPLE_DIR to the folder with photo12mp.jpg"
          : null, () async {
    final original = File("$sampleDir/photo12mp.jpg").readAsBytesSync();
    final attached = (await removeImageMetadata(original)).bytes!;
    final log = SpeedLog(frames: NoFrames());
    final preparer = ImagePreparer(log: log);

    final watch = Stopwatch()..start();
    final prepared = await preparer.prepare(attached, reduce: true);
    watch.stop();

    final reduced = prepared!.reduced!;
    expect((reduced.width, reduced.height), (2560, 1920));
    final steps = log.spans.toList().single.steps;
    // ignore: avoid_print
    print("photo12mp.jpg reduced in ${watch.elapsedMilliseconds} ms: "
        "${attached.length} -> ${reduced.bytes.length} bytes; "
        "${steps.map((s) => "${s.name} ${s.duration!.inMilliseconds} ms").join(", ")}");
  });
}
