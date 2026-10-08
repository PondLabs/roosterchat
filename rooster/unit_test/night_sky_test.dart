// The still constellation below the rail under the spaces
// (docs/whos-around-rail.md): the same sky every time, more of it in a
// taller column without the stars already there moving, none in no room.
import 'package:rooster/ui/atoms/night_sky.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a taller sky adds stars without moving the ones already there', () {
    final short = NightSkyPainter.starsFor(const Size(70, 300));
    final tall = NightSkyPainter.starsFor(const Size(70, 600));

    expect(short, isNotEmpty);
    expect(tall.length, greaterThan(short.length));
    // The unit square is scaled to the size: the same star sits twice as
    // far down in a column twice as tall.
    for (var i = 0; i < short.length; i++) {
      expect(tall[i].dx, moreOrLessEquals(short[i].dx));
      expect(tall[i].dy, moreOrLessEquals(short[i].dy * 2));
    }
    expect(NightSkyPainter.starsFor(const Size(70, 300)), equals(short));
  });

  test('no stars in no room, and never more than the list has', () {
    expect(NightSkyPainter.starsFor(Size.zero), isEmpty);
    expect(NightSkyPainter.starsFor(const Size(70, 4)), isEmpty);
    expect(NightSkyPainter.starsFor(const Size(4000, 4000)).length,
        NightSkyPainter.maxStars);
  });

  testWidgets('fills what it is given and paints', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 70, height: 500, child: NightSky()),
      ),
    ));

    expect(tester.getSize(find.byType(NightSky)), const Size(70, 500));
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
