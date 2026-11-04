import 'package:rooster/client/components/sunny_side_putt/core/effects/hawk_eye.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('marks the caster next shot wobble-free', () {
    final context = FakePowerUpContext();

    HawkEyeEffect().apply(context);

    expect(context.nextShots['caster']!.noWobble, isTrue);
    expect(context.nextShots['caster']!.isEmpty, isFalse);
  });
}
