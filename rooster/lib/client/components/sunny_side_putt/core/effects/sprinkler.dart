// Sprinkler: mark a point and every other egg near it is shoved away.

import 'dart:math' as math;

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

/// Radius around the marked point that catches eggs.
const double kSprinklerRadius = 5;

/// Push speed delivered to each egg caught in the spray.
const double kSprinklerPush = 8;

/// Shoves every egg near the marked point away from it. The caster's own
/// egg never gets wet: the engine strips it from [PowerUpContext.targetBalls].
class SprinklerEffect extends PowerUpEffect {
  const SprinklerEffect();

  @override
  String get id => 'sprinkler';

  @override
  PowerUpTiming get timing => PowerUpTiming.instant;

  @override
  bool get harmful => true;

  @override
  void apply(PowerUpContext context) {
    final target = context.target;
    if (target == null || !target.isPoint) return;
    final mark = target.point!;
    for (final ball in context.targetBalls) {
      final away = ball.position - mark;
      if (away.length > kSprinklerRadius) continue;
      final direction =
          away.length < Vec2.epsilon ? Vec2(0, -1) : away.normalized();
      context.impulseBall(
        ball.playerId,
        direction * (kSprinklerPush * math.cos(math.pi / 4)),
      );
    }
  }
}
