// Nest Swap: trade positions with a chosen player's egg, speeds preserved.

import "./../powerups.dart";


/// Swaps the caster's egg with the targeted player's egg.
class NestSwapEffect extends PowerUpEffect {
  const NestSwapEffect();

  @override
  String get id => 'nest_swap';

  @override
  PowerUpTiming get timing => PowerUpTiming.instant;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    final target = context.target;
    if (target == null || !target.isPlayer) return;
    final victim = target.playerId!;
    if (victim == context.casterId) return;
    final mine = context.ballOf(context.casterId);
    final theirs = context.ballOf(victim);
    if (mine == null || theirs == null) return;
    context.swapBalls(context.casterId, victim);
  }
}
