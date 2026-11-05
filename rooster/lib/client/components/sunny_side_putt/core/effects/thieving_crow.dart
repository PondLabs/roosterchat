// Thieving Crow: steal the first slot of a chosen player's inventory and
// hand it to the caster.

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';

/// Steals the first inventory slot of the targeted player for the caster.
class ThievingCrowEffect extends PowerUpEffect {
  const ThievingCrowEffect();

  @override
  String get id => 'thieving_crow';

  @override
  PowerUpTiming get timing => PowerUpTiming.instant;

  /// Harmful: it hurts the one it is aimed at, so a Thick Shell stops it.
  @override
  bool get harmful => true;

  @override
  void apply(PowerUpContext context) {
    final target = context.target;
    if (target == null || !target.isPlayer) return;
    if (context.shieldStops(target.playerId!)) return;
    final stolen = context.takePowerUp(target.playerId!);
    if (stolen == null) return;
    context.givePowerUp(context.casterId, stolen);
  }
}
