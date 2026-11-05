import 'package:rooster/client/components/sunny_side_putt/core/effects/sprinkler.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('sprays eggs near the marked point, pushes them away', () {
    final context = FakePowerUpContext(
      eggs: const [
        BallView(
            playerId: 'sprayed',
            position: Vec2(10, 7),
            velocity: Vec2.zero,
            holed: false),
      ],
      target: const PowerUpTarget.point(Vec2(10, 5)),
    );

    SprinklerEffect().apply(context);

    final push = context.impulses.single.deltaVelocity;
    expect(push.y, greaterThan(0)); // shoved away from the mark, downwards
  });

  test('leaves far eggs dry', () {
    final context = FakePowerUpContext(
      eggs: const [
        BallView(
            playerId: 'far',
            position: Vec2(40, 40),
            velocity: Vec2.zero,
            holed: false),
      ],
      target: const PowerUpTarget.point(Vec2(10, 5)),
    );

    SprinklerEffect().apply(context);

    expect(context.impulses, isEmpty);
  });
}
