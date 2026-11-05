// Hawk Eye: the caster's next shot never wobbles.
//
// Next-shot power-up: the engine applies-and-clears the modifier when the
// caster's next stroke fires (see `NextShotModifiers` in powerups.dart).

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';

/// Removes aim wobble from the caster's next shot.
class HawkEyeEffect extends PowerUpEffect {
  const HawkEyeEffect();

  @override
  String get id => 'hawk_eye';

  @override
  PowerUpTiming get timing => PowerUpTiming.nextShot;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    context.nextShotOf(context.casterId).noWobble = true;
  }
}
