import 'package:rooster/client/components/sunny_side_putt/core/effects/sprinkler.dart';
import 'package:rooster/client/components/sunny_side_putt/core/physics.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('leaves a spray on the marked spot for a while', () {
    final context = FakePowerUpContext(
      target: const PowerUpTarget.point(Vec2(10, 5)),
    );

    SprinklerEffect().apply(context);

    expect(context.impulses, isEmpty, reason: 'a spray, not one shove');
    final spray = context.sprays.single;
    expect(spray.center, const Vec2(10, 5));
    expect(spray.radius, kSprinklerRadius);
    expect(spray.accel, kSprinklerAccel);
    expect(
        spray.durationTicks, (kSprinklerSeconds / context.tickSeconds).round());
  });

  test('strong enough to move an egg at rest', () {
    expect(kSprinklerAccel,
        greaterThan(const PhysicsConfig().frictionDeceleration));
  });

  test('does nothing without a spot', () {
    final context = FakePowerUpContext();

    SprinklerEffect().apply(context);

    expect(context.sprays, isEmpty);
  });
}
