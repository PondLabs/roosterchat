// Ghost Egg: the caster's egg passes through walls and obstacles for a
// few seconds.

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';

/// How long the ghost state lasts, in seconds, converted to ticks with the
/// context's tick length so the duration is config-independent.
const double kGhostEggSeconds = 3;

/// Turns on the ghost flag for the caster's egg.
class GhostEggEffect extends PowerUpEffect {
  const GhostEggEffect();

  @override
  String get id => 'ghost_egg';

  @override
  PowerUpTiming get timing => PowerUpTiming.timed;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    final duration = (kGhostEggSeconds / context.tickSeconds).round();
    context.setBallFlagFor(
        context.casterId, PowerUpFlag.ghost, duration);
  }
}
