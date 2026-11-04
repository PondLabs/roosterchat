// Gust: wind in a chosen direction shoves every other egg. Harmful: the
// caster's own egg never feels it - the engine strips it from
// [PowerUpContext.targetBalls].

import "./../powerups.dart";

/// Push speed delivered to each egg caught in the gust.
const double kGustPush = 6;

/// Wind in the direction the caster chose: every other egg in play is
/// pushed that way.
class GustEffect extends PowerUpEffect {
  const GustEffect();

  @override
  String get id => 'gust';

  @override
  PowerUpTiming get timing => PowerUpTiming.instant;

  @override
  bool get harmful => true;

  @override
  void apply(PowerUpContext context) {
    final target = context.target;
    if (target == null || !target.isPoint) return;
    final wind = target.point!;
    for (final ball in context.targetBalls) {
      final push = (wind - ball.position).normalized() * kGustPush;
      context.impulseBall(ball.playerId, push);
    }
  }
}
