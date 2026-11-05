import 'package:rooster/client/components/sunny_side_putt/core/effects/nest_magnet.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('marks the caster next shot magnetic near the nest', () {
    final context = FakePowerUpContext();

    NestMagnetEffect().apply(context);

    expect(context.nextShots['caster']!.magnet, isTrue);
    expect(context.nextShots['caster']!.noWobble, isFalse);
    expect(context.nextShots['caster']!.hop, isFalse);
  });
}
