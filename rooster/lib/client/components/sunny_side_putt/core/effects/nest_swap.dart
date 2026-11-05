// Nest Swap: trade positions with a chosen player's egg, speeds preserved.

import "./../powerups.dart";

/// Swaps the caster's egg with the targeted player's egg.
class NestSwapEffect extends PowerUpEffect {
  const NestSwapEffect();

  @override
  String get id => 'nest_swap';

  @override
  PowerUpTiming get timing => PowerUpTiming.instant;

  /// Harmful: it hurts the one it is aimed at, so a Thick Shell stops it.
  @override
  bool get harmful => true;

  @override
  void apply(PowerUpContext context) {
    final target = context.target;
    if (target == null || !target.isPlayer) return;
    final victim = target.playerId!;
    if (victim == context.casterId) return;
    final mine = context.ballOf(context.casterId);
    final theirs = context.ballOf(victim);
    if (mine == null || theirs == null) return;
    if (context.shieldStops(victim)) return;
    context.swapBalls(context.casterId, victim);
  }
}
