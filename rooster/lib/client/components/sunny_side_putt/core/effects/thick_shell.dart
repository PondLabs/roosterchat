// Thick Shell: shield the caster against the next harmful effect.

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';

/// Shields the caster: the next harmful effect aimed at them is skipped.
class ThickShellEffect extends PowerUpEffect {
  const ThickShellEffect();

  @override
  String get id => 'thick_shell';

  @override
  PowerUpTiming get timing => PowerUpTiming.instant;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    context.addShield(context.casterId);
  }
}
