// A splash's rings keep to the water: they spread no further than the
// water reaches all round the spot where the egg went in.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';

void main() {
  const pond = [WaterCircle(Vec2(10, 10), 3)];

  test('in the middle of a pond the rings have room', () {
    expect(puttWaterReach(pond, const Vec2(10, 10)), 2.5);
  });

  test('near the shore they stay small', () {
    expect(puttWaterReach(pond, const Vec2(12.5, 10)), 0.4);
    expect(puttWaterReach(pond, const Vec2(12.8, 10)), 0,
        reason: 'even the smallest circle crosses the shore');
  });

  test('two waters that touch count as one', () {
    const ponds = [
      WaterRect(Rect(Vec2(0, 0), Vec2(10, 10))),
      WaterRect(Rect(Vec2(10, 0), Vec2(20, 10))),
    ];
    expect(puttWaterReach(ponds, const Vec2(10, 5)), 4.0);
  });

  test('on dry ground there is no reach', () {
    expect(puttWaterReach(pond, const Vec2(30, 30)), 0);
    expect(puttWaterReach(const [], const Vec2(10, 10)), 0);
  });
}
