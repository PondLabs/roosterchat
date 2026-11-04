// Strong Coffee: the caster's next shot gets +30% power.

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';

/// The caster's next shot gets +30% power.
class StrongCoffeeEffect extends PowerUpEffect {
  const StrongCoffeeEffect();

  /// Putt Party's +30% next-shot power boost.
  static const double powerBoost = 1.3;

  @override
  String get id => 'strong_coffee';

  @override
  PowerUpTiming get timing => PowerUpTiming.nextShot;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    context.nextShotOf(context.casterId).powerMultiplier = powerBoost;
  }
}
