import 'package:rooster/client/components/sunny_side_putt/core/effects/strong_coffee.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('boosts the caster next shot power by 30%', () {
    final context = FakePowerUpContext();

    StrongCoffeeEffect().apply(context);

    expect(context.nextShots['caster']!.powerMultiplier, closeTo(1.3, 1e-9));
  });
}
