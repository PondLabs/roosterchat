import 'package:rooster/client/components/sunny_side_putt/core/effects/chicken_hop.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('marks the caster next shot hopping over obstacles', () {
    final context = FakePowerUpContext();

    ChickenHopEffect().apply(context);

    expect(context.nextShots['caster']!.hop, isTrue);
  });
}
