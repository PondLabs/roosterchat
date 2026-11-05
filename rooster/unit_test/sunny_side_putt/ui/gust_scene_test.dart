// A Gust's wind shows the way it pushes: lanes of streaks from behind each
// egg it moves, past it toward the spot, and a feather riding along - all
// one way (round 5's council read streaks converging from all round as a
// burst with no direction).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';

void main() {
  test("a Gust's wind runs one way past each egg it pushes", () {
    final fx = PuttFxLayer();
    const egg = Vec2(10, 10);
    const spot = Vec2(30, 10);
    fx.windBehind(egg, spot);
    fx.windFeathers(egg, spot);
    expect(fx.particles.length, greaterThanOrEqualTo(14));
    for (final particle in fx.particles) {
      expect(particle.velocity.x, greaterThan(0), reason: 'toward the spot');
      expect(particle.velocity.y.abs(), lessThan(1e-9), reason: 'not across');
    }
    expect(fx.particles.where((p) => p.position.x < egg.x).length,
        greaterThanOrEqualTo(10),
        reason: 'the lanes start behind the egg and run past it');
  });
}
