// Developer mode's stream info sat over everyone's video in the top left
// for good: a click moves it round the corners, and the corner is kept.
import 'package:cockhouse/main.dart';
import 'package:cockhouse/ui/molecules/stream_debug_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  Future<void> pumpTile(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
        home: const Scaffold(
          body: SizedBox(
              width: 600,
              height: 400,
              child: StreamDebugInfo('{"is encrypted": true}')),
        ),
      ));

  Alignment corner(WidgetTester tester) => tester
      .widget<Align>(
          find.ancestor(of: find.byType(Tooltip), matching: find.byType(Align)))
      .alignment as Alignment;

  testWidgets('a click moves it round the corners', (tester) async {
    await pumpTile(tester);
    expect(corner(tester), Alignment.topLeft);

    final seen = <Alignment>[];
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('{"is encrypted": true}'));
      await tester.pumpAndSettle();
      seen.add(corner(tester));
    }

    expect(seen, [
      Alignment.topRight,
      Alignment.bottomRight,
      Alignment.bottomLeft,
      Alignment.topLeft,
    ]);
  });

  testWidgets('the corner picked is kept for the next tile', (tester) async {
    await pumpTile(tester);
    await tester.tap(find.text('{"is encrypted": true}'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await pumpTile(tester);

    expect(corner(tester), Alignment.topRight);
    expect(preferences.streamDebugInfoCorner.value, 'topRight');
  });
}
