import 'package:rooster/client/components/sunny_side_putt/core/effects/gust.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('wind shoves every other egg along the aimed direction', () {
    final context = FakePowerUpContext(
      eggs: const [
        BallView(
            playerId: 'p2',
            position: Vec2(8, 5),
            velocity: Vec2.zero,
            holed: false),
      ],
      target: const PowerUpTarget.point(Vec2(1, 0)), // wind blowing along +x
    );

    GustEffect().apply(context);

    expect(context.impulses, hasLength(1));
    expect(context.impulses.single.playerId, 'p2');
    expect(context.impulses.single.deltaVelocity.x, lessThan(0));
  });

  test('never touches the caster egg', () {
    final context = FakePowerUpContext(eggs: const [], target: null);

    GustEffect().apply(context);

    expect(context.impulses, isEmpty);
  });
}
