import 'package:rooster/client/components/sunny_side_putt/core/effects/nest_swap.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('trades the caster egg with the victim egg', () {
    final context = FakePowerUpContext(
      eggs: const [
        BallView(
            playerId: 'caster',
            position: Vec2(2, 2),
            velocity: Vec2.zero,
            holed: false),
        BallView(
            playerId: 'victim',
            position: Vec2(9, 9),
            velocity: Vec2.zero,
            holed: false),
      ],
      target: const PowerUpTarget.player('victim'),
    );

    NestSwapEffect().apply(context);

    expect(context.swaps, hasLength(1));
    expect(context.swaps.single.$1, 'caster');
    expect(context.swaps.single.$2, 'victim');
  });
}
