import 'package:rooster/client/components/sunny_side_putt/core/effects/ghost_egg.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('ghosts the caster egg for a few seconds, not walls forever', () {
    final context = FakePowerUpContext();

    GhostEggEffect().apply(context);

    expect(context.flags.single.playerId, 'caster');
    expect(context.flags.single.durationTicks,
        (kGhostEggSeconds / context.tickSeconds).round());
  });
}
