// Draws every Sunny Side Putt hole's preview PNG into
// assets/sunny_side_putt/previews/ from the course data. Rerun after a
// course changes:
//
//   cd rooster && flutter test tools/gen_putt_previews_test.dart
//
// It clears the folder first, so a removed hole's picture goes with it.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/client/components/sunny_side_putt/courses/sunny_side_putt_courses.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_course_preview.dart';

void main() {
  test('render the hole previews', () async {
    final folder = File(puttHolePreviewAsset('x')).parent;
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    folder.createSync(recursive: true);
    for (final course in sunnySidePuttCourses) {
      for (final entry in course.holes) {
        final hole = entry.hole;
        final recorder = ui.PictureRecorder();
        PuttHolePreviewPainter(hole).paint(Canvas(recorder), puttPreviewSize);
        final image = await recorder.endRecording().toImage(
            puttPreviewSize.width.toInt(), puttPreviewSize.height.toInt());
        final rgba = await image.toByteData();
        // Re-encoded as opaque RGB at the highest compression: a third of
        // the engine's own PNG.
        final decoded = img.Image.fromBytes(
            width: image.width,
            height: image.height,
            bytes: rgba!.buffer,
            numChannels: 4);
        File(puttHolePreviewAsset(hole.id)).writeAsBytesSync(
            img.encodePng(decoded.convert(numChannels: 3), level: 9));
      }
    }
  });
}
