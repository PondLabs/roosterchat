// Nest Magnet: while the caster's next shot rolls, the egg magnetizes near
// the nest - passing close bends its path in and can drop it in.
//
// Next-shot power-up: the engine applies-and-clears the modifier when the
// caster's next stroke fires (see `NextShotModifiers` in powerups.dart).

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';

/// The caster's next shot magnetizes toward the nest on close passes.
class NestMagnetEffect extends PowerUpEffect {
  const NestMagnetEffect();

  @override
  String get id => 'nest_magnet';

  @override
  PowerUpTiming get timing => PowerUpTiming.nextShot;

  @override
  bool get harmful => false;

  @override
  void apply(PowerUpContext context) {
    context.nextShotOf(context.casterId).magnet = true;
  }
}
