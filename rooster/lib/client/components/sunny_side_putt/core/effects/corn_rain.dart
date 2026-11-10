// Corn Rain: kernels pelt every other egg for a while, each one a kick in
// a random direction.

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';

/// How long the corn falls, in seconds.
const double kCornRainSeconds = 3;

/// Kernels that hit each egg over that time, the first as it is cast.
const int kCornRainKicks = 10;

/// The pace a kernel's kick adds to an egg, units/s: between the two. The
/// kicks come faster than the turf stops the egg, so they add up: an egg
/// is knocked about over some seven units of roll and ends three or four
/// from where it stood. (It used to be one kick of at most 4, 0.3 units of
/// roll on average.)
const double kCornRainMinKick = 2;
const double kCornRainKick = 4.5;

/// Pelts every egg in play with the match's seeded RNG, so replays stay
/// bit-for-bit reproducible: every kick is drawn as the power-up is cast
/// and lands on its tick. The caster's egg is never hit: the engine strips
/// it from [PowerUpContext.targetBalls].
class CornRainEffect extends PowerUpEffect {
  const CornRainEffect();

  @override
  String get id => 'corn_rain';

  @override
  PowerUpTiming get timing => PowerUpTiming.area;

  @override
  bool get harmful => true;

  @override
  void apply(PowerUpContext context) {
    final every = kCornRainSeconds / kCornRainKicks / context.tickSeconds;
    for (final ball in context.targetBalls) {
      for (var kick = 0; kick < kCornRainKicks; kick++) {
        context.nudgeBall(ball.playerId, kCornRainKick,
            minSpeed: kCornRainMinKick, delayTicks: (kick * every).round());
      }
    }
  }
}
