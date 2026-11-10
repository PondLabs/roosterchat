import 'package:rooster/client/components/sunny_side_putt/core/effects/gust.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('a wind toward the spot on every other egg, for a while', () {
    final context = FakePowerUpContext(
      eggs: const [
        BallView(
            playerId: 'p2',
            position: Vec2(8, 5),
            velocity: Vec2.zero,
            holed: false),
      ],
      target: const PowerUpTarget.point(Vec2(1, 5)),
    );

    GustEffect().apply(context);

    expect(context.impulses, isEmpty, reason: 'a wind, not one shove');
    final wind = context.pushes.single;
    expect(wind.playerId, 'p2');
    expect(wind.deltaVelocity.x, closeTo(-kGustAccel, 1e-9));
    expect(wind.deltaVelocity.y, closeTo(0, 1e-9));
    expect(
        context.pushTicks.single, (kGustSeconds / context.tickSeconds).round());
  });

  test('strong enough to move an egg at rest, and long enough to carry it', () {
    expect(kGustAccel, greaterThan(const PhysicsConfig().frictionDeceleration));
    expect(kGustSeconds, greaterThanOrEqualTo(2));
  });

  test('never touches the caster egg', () {
    final context = FakePowerUpContext(eggs: const [], target: null);

    GustEffect().apply(context);

    expect(context.pushes, isEmpty);
  });
}
