// Chicken Hop: the caster's next putt leaves the ground and flies over
// whatever is in its way (rails, rocks, hens, water, other eggs, steps)
// until it comes down, about 0.7 s later (see `NextShotModifiers` in
// powerups.dart and `PhysicsConfig.hopLift`). It used to be drawn hopping
// while it rolled into every rail like any putt.

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
