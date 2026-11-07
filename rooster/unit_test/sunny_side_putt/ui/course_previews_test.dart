import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/courses/sunny_side_putt_courses.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_course_preview.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_launch_options.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_session.dart';

void main() {
  test(
      'every hole has its preview PNG (flutter test tools/gen_putt_previews_test.dart)',
      () {
    for (final course in sunnySidePuttCourses) {
      for (final hole in course.holes) {
        expect(File(puttHolePreviewAsset(hole.hole.id)).existsSync(), isTrue,
            reason: '${hole.hole.id} has no preview');
      }
    }
  });

  testWidgets('a hole without a PNG is painted instead', (tester) async {
    final hole = sunnySidePuttCourses.first.holes.first.hole;
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
                width: 160,
                child: PuttHolePreview(
                    hole: HoleDef(
                        id: 'no_such_hole',
                        par: hole.par,
                        tee: hole.tee,
                        nest: hole.nest,
                        bounds: hole.bounds,
                        walls: hole.walls,
                        water: hole.water))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the launch options pick a course for casual', (tester) async {
    PuttLaunchOptions? options;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => options = await showPuttLaunchOptions(context),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    final course = sunnySidePuttCourses[1];
    await tester.tap(find.byKey(Key('putt-launch-course-${course.id}')));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(options!.courseId, course.id);
    final config = PuttSessionController.buildConfig(options!);
    expect(config.courses.single.id, course.id);
  });

  test('without a pick, casual still draws one course', () {
    final config = PuttSessionController.buildConfig(
        const PuttLaunchOptions(mode: GameMode.casual));
    expect(config.courses, hasLength(1));
  });
}
