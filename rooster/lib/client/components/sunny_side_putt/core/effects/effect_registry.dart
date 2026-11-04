// The twelve launch power-ups of Sunny Side Putt, in spec-table order.
library;

import '../powerups.dart';
import 'chicken_hop.dart';
import 'corn_rain.dart';
import 'ghost_egg.dart';
import 'gust.dart';
import 'hawk_eye.dart';
import 'nest_magnet.dart';
import 'nest_swap.dart';
import 'rabbit_hole.dart';
import 'sprinkler.dart';
import 'strong_coffee.dart';
import 'thick_shell.dart';
import 'thieving_crow.dart';

export 'hawk_eye.dart';
export 'nest_magnet.dart';
export 'ghost_egg.dart';
export 'chicken_hop.dart';
export 'rabbit_hole.dart';
export 'gust.dart';
export 'thick_shell.dart';
export 'strong_coffee.dart';
export 'nest_swap.dart';
export 'sprinkler.dart';
export 'corn_rain.dart';
export 'thieving_crow.dart';

/// The twelve launch effects, spec-table order.
final List<PowerUpEffect> builtinEffects = [
  HawkEyeEffect(),
  NestMagnetEffect(),
  GhostEggEffect(),
  ChickenHopEffect(),
  RabbitHoleEffect(),
  GustEffect(),
  ThickShellEffect(),
  StrongCoffeeEffect(),
  NestSwapEffect(),
  SprinklerEffect(),
  CornRainEffect(),
  ThievingCrowEffect(),
];

/// The ids of [builtinEffects], for grant-table assertions.
final Set<String> builtinEffectIds =
    builtinEffects.map((e) => e.id).toSet();

/// Registers every launch power-up into [registry].
void registerBuiltinEffects(PowerUpRegistry registry) {
  for (final effect in builtinEffects) {
    registry.register(effect);
  }
}
