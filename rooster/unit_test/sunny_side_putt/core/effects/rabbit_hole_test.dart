import 'package:rooster/client/components/sunny_side_putt/core/effects/rabbit_hole.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('teleports the caster egg to the aimed point, speed kept', () {
    final mark = Vec2(20, 8);
    final context = FakePowerUpContext(
      eggs: const [
        BallView(
            playerId: 'caster',
            position: Vec2(4, 8),
            velocity: Vec2.zero,
            holed: false),
      ],
      target: PowerUpTarget.point(mark),
    );

    RabbitHoleEffect().apply(context);

    expect(context.teleports, hasLength(1));
    expect(context.teleports.single.deltaVelocity, Vec2(10, 8));
  });

  test('without an aim it does nothing', () {
    final context = FakePowerUpContext();

    RabbitHoleEffect().apply(context);

    expect(context.teleports, isEmpty);
  });
}
