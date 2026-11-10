import 'package:rooster/client/components/sunny_side_putt/core/effects/corn_rain.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';
import 'fake_context.dart';
import 'package:test/test.dart';

void main() {
  test('kernel after kernel on every egg but the caster, spread over its time',
      () {
    // The engine hands the effect the caster-free egg list, so the fake
    // mirrors that: only p2's egg is in the target set.
    final context = FakePowerUpContext(
      eggs: const [
        BallView(
            playerId: 'p2',
            position: Vec2(8, 5),
            velocity: Vec2.zero,
            holed: false),
      ],
    );

    CornRainEffect().apply(context);

    expect(context.nudges, hasLength(kCornRainKicks));
    expect(context.nudges.every((nudge) => nudge.playerId == 'p2'), isTrue);
    expect(
        context.nudges.every((nudge) => nudge.deltaVelocity.x == kCornRainKick),
        isTrue);
    expect(context.nudgeMinSpeeds.every((speed) => speed == kCornRainMinKick),
        isTrue);
    // The first as it is cast, the last near the end of the rain.
    expect(context.nudgeDelays.first, 0);
    final ticks = kCornRainSeconds / context.tickSeconds;
    expect(context.nudgeDelays.last, inInclusiveRange(ticks * 0.8, ticks));
    for (var i = 1; i < context.nudgeDelays.length; i++) {
      expect(context.nudgeDelays[i], greaterThan(context.nudgeDelays[i - 1]));
    }
  });
}
