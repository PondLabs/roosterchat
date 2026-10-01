// The desktop sidebar is as wide as the user drags it, within limits, and
// stays that wide after a restart.
import 'package:cockhouse/main.dart';
import 'package:cockhouse/ui/atoms/resizable_width.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => const MaterialApp(
      home: Scaffold(
        body: Row(children: [_Sidebar(), Expanded(child: SizedBox())]),
      ),
    );

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) => ResizableWidth(
        preference: preferences.sidebarWidth,
        min: 270,
        max: 550,
        child: const Text(
          "a channel name far too long to fit in the sidebar at any width",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
}

double _width(WidgetTester tester) =>
    tester.getSize(find.byType(ResizableWidth)).width;

Future<void> _drag(WidgetTester tester, double dx) async {
  await tester.drag(find.byKey(ResizableWidth.handleKey), Offset(dx, 0));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets('starts at the default width', (tester) async {
    await tester.pumpWidget(_app());
    expect(_width(tester), 320);
  });

  testWidgets('dragging the handle resizes and saves', (tester) async {
    await tester.pumpWidget(_app());
    await _drag(tester, 60);
    expect(_width(tester), 380);
    expect(preferences.sidebarWidth.value, 380);
  });

  testWidgets('width is clamped to min and max', (tester) async {
    await tester.pumpWidget(_app());
    await _drag(tester, 1000);
    expect(_width(tester), 550);
    expect(preferences.sidebarWidth.value, 550);

    await _drag(tester, -1000);
    expect(_width(tester), 270);
    expect(preferences.sidebarWidth.value, 270);
    expect(tester.takeException(), isNull, reason: 'nothing overflows');
  });

  testWidgets('saved width comes back on rebuild', (tester) async {
    await tester.pumpWidget(_app());
    await _drag(tester, 100);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app());
    expect(_width(tester), 420);
  });

  testWidgets('double-clicking the handle resets the width', (tester) async {
    await tester.pumpWidget(_app());
    await _drag(tester, 100);
    final handle = find.byKey(ResizableWidth.handleKey);
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(_width(tester), 320);
    expect(preferences.sidebarWidth.value, 320);
  });
}
