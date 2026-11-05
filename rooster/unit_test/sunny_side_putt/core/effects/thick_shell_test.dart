import 'package:rooster/client/components/sunny_side_putt/core/effects/thick_shell.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('shields the caster against the next harmful effect', () {
    final context = FakePowerUpContext();

    const ThickShellEffect().apply(context);

    expect(context.shields.single, 'caster');
  });
}
