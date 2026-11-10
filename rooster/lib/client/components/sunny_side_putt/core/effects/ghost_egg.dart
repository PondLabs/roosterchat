// Ghost Egg: the caster's next putt passes through rails, rocks and hens
// until the egg comes to rest.
//
// Next-shot power-up: the engine applies-and-clears the modifier when the
// caster's next stroke fires (see `NextShotModifiers` in powerups.dart). It
// used to switch the ghost on for three seconds from the cast: the three
// seconds ran out while its player was still aiming.

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';

/// The caster's next shot passes through rails, rocks and hens. An egg that
/// rests where none can stand (inside a rock, in a hedge, past the fence)
/// comes back out at the nearest turf.
class GhostEggEffect extends PowerUpEffect {
  const GhostEggEffect();

  @override
  String get id => 'ghost_egg';

  @override
  PowerUpTiming get timing => PowerUpTiming.nextShot;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    context.nextShotOf(context.casterId).ghost = true;
  }
}
