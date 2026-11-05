// A PowerUpContext double that records every mutation an effect makes, so
// effect tests can assert exactly who was touched and how.
library;

import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rng.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

/// One recorded impulse or nudge, kept per player.
class RecordedImpulse {
  final String playerId;
  final Vec2 deltaVelocity;

  const RecordedImpulse(this.playerId, this.deltaVelocity);
}

/// One recorded setBallFlagFor call.
class RecordedFlag {
  final String playerId;
  final PowerUpFlag flag;
  final int durationTicks;

  const RecordedFlag(this.playerId, this.flag, this.durationTicks);
}

/// One recorded givePowerUp grant.
class RecordedGrant {
  final String playerId;
  final String effectId;

  const RecordedGrant(this.playerId, this.effectId);
}

/// A [PowerUpContext] whose world is whatever eggs the test hands in and
/// whose mutations are all recorded for assertions.
class FakePowerUpContext implements PowerUpContext {
  FakePowerUpContext({this.eggs = const [], this.target});

  /// Eggs an effect may hit, as the engine would hand them over.
  final List<BallView> eggs;

  /// What the caster aimed at, when the effect takes a target.
  @override
  final PowerUpTarget? target;

  /// Recorded [impulseBall] calls.
  final impulses = <RecordedImpulse>[];

  /// Recorded [nudgeBall] calls, as player-id + capped-speed pairs.
  final nudges = <RecordedImpulse>[];

  /// Recorded [teleportBall] destinations.
  final teleports = <RecordedImpulse>[];

  /// Recorded [setBallFlagFor] calls.
  final flags = <RecordedFlag>[];

  /// Recorded [addShield] calls.
  final shields = <String>[];

  /// Recorded [swapBalls] calls.
  final swaps = <(String, String)>[];

  /// Recorded [givePowerUp] grants.
  final grants = <RecordedGrant>[];

  /// The single inventory a [takePowerUp] steals from, keyed per player.
  final Map<String, List<String>> inventories = {};

  @override
  String get casterId => 'caster';

  @override
  int get tick => 0;

  @override
  double get tickSeconds => 1 / 120;

  @override
  List<BallView> get targetBalls => List.unmodifiable(eggs);

  @override
  BallView? ballOf(String playerId) {
    for (final egg in eggs) {
      if (egg.playerId == playerId) return egg;
    }
    return null;
  }

  /// Per-player next-shot modifiers, so next-shot effects can be asserted.
  final nextShots = <String, NextShotModifiers>{};

  @override
  GameRng get rng => GameRng.seeded(4242);

  @override
  NextShotModifiers nextShotOf(String playerId) =>
      nextShots.putIfAbsent(playerId, NextShotModifiers.new);

  @override
  void impulseBall(String playerId, Vec2 deltaVelocity) =>
      impulses.add(RecordedImpulse(playerId, deltaVelocity));

  @override
  void nudgeBall(String playerId, double maxSpeed) =>
      nudges.add(RecordedImpulse(playerId, Vec2(maxSpeed, 0)));

  @override
  void teleportBall(String playerId, Vec2 to) =>
      teleports.add(RecordedImpulse(playerId, to));

  @override
  void swapBalls(String playerIdA, String playerIdB) =>
      swaps.add((playerIdA, playerIdB));

  @override
  void setBallFlagFor(String playerId, PowerUpFlag flag, int durationTicks) =>
      flags.add(RecordedFlag(playerId, flag, durationTicks));

  @override
  bool givePowerUp(String playerId, String effectId) {
    (inventories[playerId] ??= []).add(effectId);
    return true;
  }

  @override
  String? takePowerUp(String playerId) => inventories[playerId]?.isEmpty ?? true
      ? null
      : inventories[playerId]!.removeAt(0);

  @override
  void removePowerUp(String playerId, String effectId) {
    inventories[playerId]?.remove(effectId);
  }

  @override
  bool hasPowerUp(String playerId, String effectId) =>
      inventories[playerId]?.contains(effectId) ?? false;

  @override
  void addShield(String playerId) => shields.add(playerId);

  /// Players whose shell stops the cast (and which the fake spent).
  final Set<String> shelled = {};
  final List<String> stoppedBy = [];

  @override
  bool shieldStops(String playerId) {
    if (playerId == casterId || !shelled.remove(playerId)) return false;
    stoppedBy.add(playerId);
    return true;
  }
}
