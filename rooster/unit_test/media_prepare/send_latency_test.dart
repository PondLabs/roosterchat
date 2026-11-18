import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_attachment_files.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import 'fakes.dart';
import 'send_harness.dart';

/// From Send to the first byte of the 12 MP photo's upload reaching the
/// transport (the SDK's fake homeserver), with the preparation already
/// done and with it starting at Send. Three runs each; the median must be
/// under 500 ms.
///
/// Send here is what `ChatState.sendMessage` and `MatrixRoom` do with an
/// attachment: read its Exif for the location question, make the files to
/// send, and `sendFileEvent`.
///
/// The photo is not in the repository: point SPEED_SAMPLE_DIR at a folder
/// holding `photo12mp.jpg`, or the test is skipped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment["SPEED_SAMPLE_DIR"];

  for (final ready in [true, false]) {
    final label = ready ? "preparation ready" : "preparation starting at Send";
    test("12 MP photo, $label: Send to first upload byte under 500 ms",
        skip: dir == null
            ? "SPEED_SAMPLE_DIR is not set: no 12 MP photo to send"
            : null, () async {
      final photo = File("$dir/photo12mp.jpg").readAsBytesSync();
      final times = <int>[];
      for (var run = 0; run < 3; run++) {
        final clock = Stopwatch()..start();
        final harness = await SendHarness.start(clock);
        final preparer = ImagePreparer(log: SpeedLog(frames: NoFrames()));
        final attachment = PendingFileAttachment(
            name: "photo.jpg", data: photo, size: photo.length);
        if (ready) {
          await attachment.startImagePreparation(preparer: preparer);
        }

        final send = clock.elapsed;
        await readExifFromBytes(attachment.data!);
        final processed =
            (await matrixFilesForAttachment(attachment, preparer: preparer))!;
        final sent = harness.room
            .sendFileEvent(processed.file, thumbnail: processed.thumbnailFile);
        final firstByte = await harness.transport.firstUpload;
        await sent;
        times.add((firstByte - send).inMilliseconds);

        expect(processed.thumbnailFile, isNotNull);
        expect(harness.transport.uploads.first.bytes.length, photo.length);
        expect(harness.sdkImagePasses, 0);
        await harness.dispose();
      }
      final sorted = [...times]..sort();
      // ignore: avoid_print
      print("$label: Send to first upload byte $times ms, "
          "median ${sorted[1]} ms");
      expect(sorted[1], lessThan(500));
    });
  }
}
