import 'package:rooster/client/components/sunny_side_putt/core/effects/thieving_crow.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('steals the first inventory slot of the marked victim', () {
    final context = FakePowerUpContext(
      eggs: const [
        BallView(
            playerId: 'victim',
            position: Vec2(8, 5),
            velocity: Vec2.zero,
            holed: false),
      ],
      target: PowerUpTarget.player('victim'),
    );
    context.inventories['victim'] = ['hawk_eye', 'nest_magnet'];

    ThievingCrowEffect().apply(context);

    expect(context.inventories['caster'], ['hawk_eye']);
    expect(context.inventories['victim'], ['nest_magnet']);
  });

  test('an empty-handed victim leaves the caster with nothing', () {
    final context = FakePowerUpContext(target: null);

    ThievingCrowEffect().apply(context);

    expect(context.grants, isEmpty);
  });
}
