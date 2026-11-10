import 'package:rooster/client/components/sunny_side_putt/core/effects/ghost_egg.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('arms the caster next shot, with no clock running on the aim', () {
    final context = FakePowerUpContext();

    GhostEggEffect().apply(context);

    expect(context.nextShots['caster']!.ghost, isTrue);
    expect(context.flags, isEmpty,
        reason: 'no timed flag: it used to run out before the putt');
  });
}
