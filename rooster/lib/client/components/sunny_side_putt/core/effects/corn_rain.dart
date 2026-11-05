// Corn Rain: kernels bounce around the hole, nudging every egg in a
// random direction.

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';

/// Cap on the random speed a kernel kick adds to an egg.
const double kCornRainKick = 4;

/// Nudges every egg in play with the match's seeded RNG, so replays stay
/// bit-for-bit reproducible. The caster's egg is never nudged: the engine
/// strips it from [PowerUpContext.targetBalls].
class CornRainEffect extends PowerUpEffect {
  const CornRainEffect();

  @override
  String get id => 'corn_rain';

  @override
  PowerUpTiming get timing => PowerUpTiming.instant;

  @override
  bool get harmful => true;

  @override
  void apply(PowerUpContext context) {
    for (final ball in context.targetBalls) {
      context.nudgeBall(ball.playerId, kCornRainKick);
    }
  }
}
