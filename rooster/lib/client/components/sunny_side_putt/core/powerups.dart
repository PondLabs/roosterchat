// The power-up contract of Sunny Side Putt. The twelve effects themselves
// live in `core/effects/` (their own ticket); this file is the seam they
// plug into and everything the rules engine needs to run matches without
// a single effect registered: the inventory with its cap of 3, the
// next-shot modifiers the engine applies on the caster's next stroke, and
// the context an effect receives when cast.
//
// HARD RULES the engine enforces (effects must also respect them):
//   * The caster never suffers their own negative effect: harmful effects
//     are handed [PowerUpContext.targetBalls] with the caster already
//     removed, and [PowerUpEffect.apply] must skip the caster too - the
//     caster id travels in the context for exactly that check.
//   * A shielded egg (Thick Shell) is skipped by harmful effects; the
//     engine consumes the shield when filtering targets.
//   * The inventory caps at 3; a pickup beyond the cap is discarded (the
//     engine says so with an event).
//
// Everything is deterministic: effects get their randomness only from
// [PowerUpContext.rng], the match's seeded generator.
library;

import 'rng.dart';
import 'vec.dart';

/// Transient per-egg states power-ups switch on. `ghost` passes through
/// rails, rocks and hens until the egg rests; `hop` flies over them while
/// the putt is in the air; `magnet` pulls the egg toward the nest when it
/// passes near. See `physics.dart` for how each changes the simulation.
/// (An egg that ends a ghost roll or a hop where none can stand comes back
/// out at the nearest turf: see `reach.dart`.)
enum PowerUpFlag { ghost, hop, magnet }

/// When an effect acts.
enum PowerUpTiming {
  /// Modifies the caster's next shot (Hawk Eye, Strong Coffee, Chicken Hop,
  /// Nest Magnet, Ghost Egg): applied when that shot fires, then cleared.
  /// One armed and not yet putted goes on to the next hole with its player
  /// (their egg dropped in before they could use it), but not to the next
  /// course, which everyone starts clean.
  nextShot,

  /// Acts immediately when cast, on no particular egg (Rabbit Hole on self,
  /// Nest Swap, Thieving Crow).
  instant,

  /// Switches a timed state on and lets it run out (Thick Shell).
  timed,

  /// Acts on every other egg within reach, for a while (Gust, Sprinkler,
  /// Corn Rain).
  area,
}

/// What an effect aims at: another player's egg, or a point on the green.
class PowerUpTarget {
  final String? playerId;
  final Vec2? point;

  const PowerUpTarget.player(String this.playerId) : point = null;
  const PowerUpTarget.point(Vec2 this.point) : playerId = null;

  bool get isPlayer => playerId != null;
  bool get isPoint => point != null;
}

/// Read-only look at one egg, for effects to inspect and aim.
class BallView {
  final String playerId;
  final Vec2 position;
  final Vec2 velocity;
  final bool holed;

  const BallView(
      {required this.playerId,
      required this.position,
      required this.velocity,
      required this.holed});

  double get speed => velocity.length;
}

/// The world as an effect may touch it. The rules engine builds one per
/// cast; every mutation goes through here so it stays deterministic and
/// journalled like any other input.
abstract class PowerUpContext {
  /// Who cast the effect. Harmful effects MUST NOT touch this egg.
  String get casterId;

  /// What the caster aimed at, when the effect takes a target.
  PowerUpTarget? get target;

  /// The current physics tick of the hole (for timed effects).
  int get tick;

  /// Seconds per physics tick, to convert durations.
  double get tickSeconds;

  /// The match's seeded generator - the only randomness an effect may use.
  GameRng get rng;

  /// The eggs an effect may hit: every egg in play; for harmful effects the
  /// caster and shielded players are already removed (shields consumed).
  List<BallView> get targetBalls;

  BallView? ballOf(String playerId);

  // ---- mutations ---------------------------------------------------------

  /// Adds [deltaVelocity] to an egg's velocity.
  void impulseBall(String playerId, Vec2 deltaVelocity);

  /// Kicks an egg in a random direction, between [minSpeed] and [maxSpeed],
  /// [delayTicks] from now (Corn Rain's kernels, one after another).
  void nudgeBall(String playerId, double maxSpeed,
      {double minSpeed = 0, int delayTicks = 0});

  /// A wind on one egg: [accel] (units/s^2) for [durationTicks] (Gust).
  void pushBall(String playerId, Vec2 accel, int durationTicks);

  /// A spray on the green for [durationTicks] (Sprinkler): every egg within
  /// [radius] of [center] is pushed away from it at [accel] (units/s^2),
  /// the ones that roll into it later too. Never the caster's, nor one
  /// whose shell stopped the cast.
  void spray(Vec2 center, double radius, double accel, int durationTicks);

  /// Moves an egg somewhere instantly, speed preserved (Rabbit Hole).
  void teleportBall(String playerId, Vec2 to);

  /// Swaps two eggs' positions, speeds preserved (Nest Swap).
  void swapBalls(String playerIdA, String playerIdB);

  /// Switches [flag] on for an egg: for [durationTicks] ticks (Ghost Egg).
  void setBallFlagFor(String playerId, PowerUpFlag flag, int durationTicks);

  /// The caster's pending next-shot modifiers, to mutate in place.
  NextShotModifiers nextShotOf(String playerId);

  /// Adds an effect to a player's inventory. False when the cap spilled it.
  bool givePowerUp(String playerId, String effectId);

  /// Removes and returns the FIRST inventory slot (Thieving Crow steals
  /// the first slot; using a power-up consumes it too).
  String? takePowerUp(String playerId);

  /// Removes the first matching effect from a player's inventory.
  void removePowerUp(String playerId, String effectId);

  bool hasPowerUp(String playerId, String effectId);

  /// Grants a shield for [durationTicks] of the hole's play: the next
  /// harmful effect aimed at this egg is skipped (Thick Shell). It ends
  /// with the hole at the latest.
  void addShield(String playerId, int durationTicks);

  /// Whether [playerId]'s shell stops this cast, for an effect aimed at one
  /// player (a theft, a swap): a harmful effect spends one of their shields
  /// and the engine tells it as [ShieldBlocked]; the effect then does
  /// nothing to them. (Area effects meet shields in [targetBalls].)
  bool shieldStops(String playerId);
}

/// One of the twelve (or any future) effects.
abstract class PowerUpEffect {
  const PowerUpEffect();

  String get id;

  PowerUpTiming get timing;

  /// Whether this effect can hurt the eggs it reaches. Harmful effects
  /// never hit their caster and are blocked by shields; the engine
  /// enforces both when building the context.
  bool get harmful;

  void apply(PowerUpContext context);
}

/// The known effects, in registration order (which is also the order the
/// "?" boxes draw from). The rules engine holds one; effects register
/// themselves at match setup.
class PowerUpRegistry {
  final Map<String, PowerUpEffect> _effects = {};
  final List<String> _grantable = [];

  // Not const: a registered effect must never leak into another registry
  // through Dart's canonicalized const instances.

  void register(PowerUpEffect effect, {bool grantable = true}) {
    _effects[effect.id] = effect;
    if (grantable && !_grantable.contains(effect.id)) {
      _grantable.add(effect.id);
    }
  }

  PowerUpEffect? byId(String id) => _effects[id];

  List<String> get grantableIds => List.unmodifiable(_grantable);

  /// A random grantable effect id, or null when nothing is registered -
  /// "?" boxes then only fire their pickup event.
  String? randomGrantable(GameRng rng) =>
      _grantable.isEmpty ? null : _grantable[rng.nextInt(_grantable.length)];
}

/// What happens differently on a player's next shot, granted by nextShot
/// power-ups and consumed (all of it, in one shot) when that shot fires.
class NextShotModifiers {
  /// Hawk Eye: the engine skips the aim wobble.
  bool noWobble;

  /// Strong Coffee: multiplies the shot's speed (1.3). Resets to 1 after.
  double powerMultiplier;

  /// Chicken Hop: the shot leaves the ground and flies over whatever is in
  /// its way until it comes down.
  bool hop;

  /// Nest Magnet: the egg magnetizes near the nest until it settles.
  bool magnet;

  /// Ghost Egg: the shot passes through rails, rocks and hens until the
  /// egg settles.
  bool ghost;

  NextShotModifiers(
      {this.noWobble = false,
      this.powerMultiplier = 1,
      this.hop = false,
      this.magnet = false,
      this.ghost = false});

  bool get isEmpty =>
      !noWobble && powerMultiplier == 1 && !hop && !magnet && !ghost;

  void clear() {
    noWobble = false;
    powerMultiplier = 1;
    hop = false;
    magnet = false;
    ghost = false;
  }

  /// Takes [json]'s values (as [toJson] wrote them).
  void restore(Map<Object?, Object?> json) {
    noWobble = json['noWobble'] == true;
    powerMultiplier = (json['powerMultiplier'] as num?)?.toDouble() ?? 1;
    hop = json['hop'] == true;
    magnet = json['magnet'] == true;
    ghost = json['ghost'] == true;
  }

  Map<String, Object?> toJson() => {
        'noWobble': noWobble,
        'powerMultiplier': powerMultiplier,
        'hop': hop,
        'magnet': magnet,
        'ghost': ghost,
      };

  factory NextShotModifiers.fromJson(Map<Object?, Object?> json) =>
      NextShotModifiers()..restore(json);
}

/// A player's held power-ups, first-in first-used, capped at 3.
class PowerUpInventory {
  static const int cap = 3;

  final List<String> _items = [];

  /// Adds to the end. False when the inventory is full and the effect was
  /// discarded (contract: extras are dropped, never bump others out).
  bool add(String effectId) {
    if (_items.length >= cap) return false;
    _items.add(effectId);
    return true;
  }

  /// Removes and returns the first slot, or null when empty.
  String? takeFirst() => _items.isEmpty ? null : _items.removeAt(0);

  /// Removes the first slot matching [effectId]; true when one was there.
  bool removeById(String effectId) {
    final index = _items.indexOf(effectId);
    if (index < 0) return false;
    _items.removeAt(index);
    return true;
  }

  bool contains(String effectId) => _items.contains(effectId);

  int get length => _items.length;

  bool get isEmpty => _items.isEmpty;

  bool get isFull => _items.length >= cap;

  List<String> toList() => List.unmodifiable(_items);

  List<String> toJson() => List.of(_items);

  void restore(List<Object?> items) {
    _items
      ..clear()
      ..addAll(items.cast<String>());
  }

  @override
  String toString() => 'PowerUpInventory$_items';
}
