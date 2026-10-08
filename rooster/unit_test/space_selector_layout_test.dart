// The space column's trailing widget (the rail under the spaces,
// docs/whos-around-rail.md) comes right after the footer, and the filler
// (the night sky) takes what is left down to the column's bottom, and
// nothing once the list is longer than the column.
import 'package:rooster/ui/molecules/space_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const trailing = ValueKey('trailing');
  const footer = ValueKey('footer');
  const filler = ValueKey('filler');

  Future<void> show(WidgetTester tester, {required double headerHeight}) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 70,
            height: 400,
            child: SpaceSelector(
              const [],
              width: 70,
              header: SizedBox(height: headerHeight),
              footer: const SizedBox(key: footer, height: 50),
              trailing: const SizedBox(key: trailing, height: 40, width: 70),
              filler: const ColoredBox(key: filler, color: Colors.black),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets(
      'the trailing widget follows the footer, and the filler takes the rest '
      'of a short column', (tester) async {
    await show(tester, headerHeight: 100);

    final footerBottom = tester.getBottomLeft(find.byKey(footer)).dy;
    expect(footerBottom, lessThan(300));
    expect(tester.getTopLeft(find.byKey(trailing)).dy,
        moreOrLessEquals(footerBottom));
    expect(tester.getTopLeft(find.byKey(filler)).dy,
        moreOrLessEquals(footerBottom + 40));
    expect(tester.getBottomLeft(find.byKey(filler)).dy, moreOrLessEquals(400));
  });

  testWidgets('the filler gets no room in a long column', (tester) async {
    await show(tester, headerHeight: 1000);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(
        tester.getBottomLeft(find.byKey(trailing)).dy, moreOrLessEquals(400));
    expect(tester.getBottomLeft(find.byKey(footer)).dy, moreOrLessEquals(360));
    // Off stage, as a sliver of no extent is.
    expect(tester.getSize(find.byKey(filler, skipOffstage: false)).height, 0);
  });
}
