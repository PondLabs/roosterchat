// Chicken Hop: the caster's next shot flies over obstacles until the egg
// settles (see `NextShotModifiers` in powerups.dart).

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';

/// The caster's next shot flies over obstacles.
class ChickenHopEffect extends PowerUpEffect {
  const ChickenHopEffect();

  @override
  String get id => 'chicken_hop';

  @override
  PowerUpTiming get timing => PowerUpTiming.nextShot;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    context.nextShotOf(context.casterId).hop = true;
  }
}
