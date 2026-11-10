// Sprinkler: mark a spot; for a while every other egg near it is pushed
// away, the ones that roll into the spray later too.

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';

/// Radius around the marked point the spray reaches.
const double kSprinklerRadius = 5;

/// How long the sprinkler runs, in seconds.
const double kSprinklerSeconds = 3;

/// The spray's push on an egg inside it (units/s^2): 5 over the rolling
/// friction (7), enough to drive an egg from the middle out past the edge.
/// (It used to be one shove of 5.7 units/s, spent within 2.3 units.)
const double kSprinklerAccel = 12;

/// Sprays around the marked point. The caster's own egg never gets wet,
/// nor one whose shell stopped the cast.
class SprinklerEffect extends PowerUpEffect {
  const SprinklerEffect();

  @override
  String get id => 'sprinkler';

  @override
  PowerUpTiming get timing => PowerUpTiming.area;

  @override
  bool get harmful => true;

  @override
  void apply(PowerUpContext context) {
    final target = context.target;
    if (target == null || !target.isPoint) return;
    context.spray(
      target.point!,
      kSprinklerRadius,
      kSprinklerAccel,
      (kSprinklerSeconds / context.tickSeconds).round(),
    );
  }
}
