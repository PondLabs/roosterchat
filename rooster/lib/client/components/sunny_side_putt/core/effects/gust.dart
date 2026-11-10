// Gust: a wind toward a chosen spot carries every other egg along for a
// while. Harmful: the caster's own egg never feels it - the engine strips
// it from [PowerUpContext.targetBalls].

import "./../powerups.dart";

/// How long the wind blows, in seconds.
const double kGustSeconds = 2.5;

/// The wind's push on each egg it catches (units/s^2): 2.5 over the rolling
/// friction (7), so an egg at rest in the open is carried about ten units,
/// most of it while the wind still blows. (It used to be one shove of 6
/// units/s, spent within 2.6 units.)
const double kGustAccel = 9.5;

/// Wind toward the spot the caster chose: every other egg in play is
/// carried that way, each along its own line to the spot as the cast found
/// it.
class GustEffect extends PowerUpEffect {
  const GustEffect();

  @override
  String get id => 'gust';

  @override
  PowerUpTiming get timing => PowerUpTiming.area;

  @override
  bool get harmful => true;

  @override
  void apply(PowerUpContext context) {
    final target = context.target;
    if (target == null || !target.isPoint) return;
    final wind = target.point!;
    final ticks = (kGustSeconds / context.tickSeconds).round();
    for (final ball in context.targetBalls) {
      final push = (wind - ball.position).normalized() * kGustAccel;
      context.pushBall(ball.playerId, push, ticks);
    }
  }
}
