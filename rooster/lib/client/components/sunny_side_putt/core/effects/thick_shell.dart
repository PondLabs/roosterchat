// Thick Shell: shield the caster against the next harmful effect, for a
// while.

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';

/// How long the shell holds, in seconds of the hole's play. It also ends
/// when it has stopped one cast, and with the hole. (It used to hold until
/// it stopped a cast, however many holes and courses later.)
const double kThickShellSeconds = 30;

/// Shields the caster: the next harmful effect aimed at them is skipped.
class ThickShellEffect extends PowerUpEffect {
  const ThickShellEffect();

  @override
  String get id => 'thick_shell';

  @override
  PowerUpTiming get timing => PowerUpTiming.timed;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    context.addShield(
        context.casterId, (kThickShellSeconds / context.tickSeconds).round());
  }
}
