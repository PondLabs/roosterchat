import 'package:cockhouse/ui/molecules/soundboard_trim_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

(int, int) move(int startMs, int endMs,
        {required bool start, required int ms}) =>
    SoundboardTrimEditor.moveEdge(
        durationMs: 60000,
        startMs: startMs,
        endMs: endMs,
        start: start,
        ms: ms);

void main() {
  group('moveEdge', () {
    test('moves one edge inside the limits', () {
      expect(move(0, 10000, start: true, ms: 2000), (2000, 10000));
      expect(move(0, 10000, start: false, ms: 12000), (0, 12000));
    });

    test('dragging past 15 s pulls the other edge along', () {
      expect(move(0, 10000, start: false, ms: 20000), (5000, 20000));
      expect(move(30000, 40000, start: true, ms: 20000), (20000, 35000));
    });

    test('keeps at least 100 ms selected', () {
      expect(move(1000, 5000, start: true, ms: 5000), (5000, 5100));
      expect(move(1000, 5000, start: false, ms: 1000), (900, 1000));
    });

    test('stays inside the source', () {
      expect(move(0, 10000, start: true, ms: -500), (0, 10000));
      expect(move(50000, 59000, start: false, ms: 70000), (50000, 60000));
    });
  });

  testWidgets('dragging a handle reports the new selection', (tester) async {
    (int, int)? changed;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: SizedBox(
          width: 600,
          child: SoundboardTrimEditor(
            durationMs: 60000,
            peaks: List.filled(100, 0.5),
            startMs: 0,
            endMs: 15000,
            onChanged: (s, e) => changed = (s, e),
          ),
        ),
      ),
    ));

    // The end handle sits at 15/60 of 600 px; drag it 30 px left (3 s).
    final box = tester.getTopLeft(find.descendant(
        of: find.byType(SoundboardTrimEditor),
        matching: find
            .byWidgetPredicate((w) => w is CustomPaint && w.painter != null)));
    final handle = box + const Offset(150, SoundboardTrimEditor.height / 2);
    await tester.dragFrom(handle, const Offset(-30, 0));
    expect(changed, (0, 12000));
  });
}
