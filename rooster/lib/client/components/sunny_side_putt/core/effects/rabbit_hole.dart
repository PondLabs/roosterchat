// Rabbit Hole: teleport the caster's egg toward the marked point.

import "./../powerups.dart";


/// Furthest single hop, in world units.
const double kRabbitHoleMaxDistance = 6;

/// Teleports the caster's egg toward the marked point, clamped to
/// [kRabbitHoleMaxDistance] units. Speed is preserved by the world.
class RabbitHoleEffect extends PowerUpEffect {
  const RabbitHoleEffect();

  @override
  String get id => 'rabbit_hole';

  @override
  PowerUpTiming get timing => PowerUpTiming.instant;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    final target = context.target;
    if (target == null || !target.isPoint) return;
    final self = context.ballOf(context.casterId);
    if (self == null) return;

    var delta = target.point! - self.position;
    if (delta.length > kRabbitHoleMaxDistance) {
      delta = delta.scaledTo(kRabbitHoleMaxDistance);
    }
    context.teleportBall(context.casterId, self.position + delta);
  }
}
