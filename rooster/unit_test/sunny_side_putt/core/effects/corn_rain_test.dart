import 'package:rooster/client/components/sunny_side_putt/core/effects/corn_rain.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('randomly nudges every egg but the caster with the seeded rng', () {
    // The engine hands the effect the caster-free egg list, so the fake
    // mirrors that: only p2's egg is in the target set.
    final context = FakePowerUpContext(
      eggs: const [
        BallView(
            playerId: 'p2',
            position: Vec2(8, 5),
            velocity: Vec2.zero,
            holed: false),
      ],
    );

    CornRainEffect().apply(context);

    expect(context.nudges, hasLength(1));
    expect(context.nudges.single.playerId, 'p2');
    expect(context.nudges.single.deltaVelocity.x, kCornRainKick);
  });
}
