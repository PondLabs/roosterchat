// Power-up targeting in Sunny Side Putt: which effects need a spot on the
// green or another player before they can be cast, the state between the
// slot's tap and the press (or pick) that casts, and the checks that keep
// a cast that could do nothing from spending the power-up.
//
// The flow: a tap on a slot casts a no-target effect at once; a point
// effect (Rabbit Hole, Gust, Sprinkler) is ARMED, and the next primary
// press on the green casts it there instead of starting an aim (Esc, a
// right click or the armed slot tapped again cancels); a player effect
// (Nest Swap, Thieving Crow) opens the HUD's picker, which casts on the
// player picked. Nothing is spent until the cast itself, and only while a
// hole is being played.
library;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/components/sunny_side_putt/core/powerups.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/client/components/sunny_side_putt/core/vec.dart';

import 'putt_match.dart';

/// What an effect needs from the player before it can be cast.
enum PuttPowerAim {
  /// Nothing: a tap casts it.
  none,

  /// A spot on the green.
  point,

  /// Another player.
  player,
}

/// The aim each of the twelve effects takes; unknown ids cast at once.
PuttPowerAim puttPowerAimOf(String effectId) => switch (effectId) {
      'rabbit_hole' || 'gust' || 'sprinkler' => PuttPowerAim.point,
      'nest_swap' || 'thieving_crow' => PuttPowerAim.player,
      _ => PuttPowerAim.none,
    };

/// A cast that went through: the effect, its target (null for the ones
/// that take none) and where my egg was before it (a Rabbit Hole moves it).
typedef PuttCast = void Function(
    String effectId, PowerUpTarget? target, Vec2? myEggBefore);

/// The targeting state the HUD shows and the view's pointer plumbing
/// reads. A [ChangeNotifier]: the HUD rebuilds when a slot arms, a picker
/// opens or either goes away.
class PuttTargeting extends ChangeNotifier {
  /// Told after every cast that went through, for the game's bursts.
  PuttCast? onCast;

  String? _armed;
  int? _armedSlot;
  String? _picking;
  int? _pickingSlot;
  Vec2? _hover;
  String? _notice;
  int _noticeSerial = 0;

  /// The point effect waiting for its spot.
  String? get armed => _armed;

  /// The slot [armed] came from: the one that glows.
  int? get armedSlot => _armedSlot;

  /// The player effect whose picker is open.
  String? get picking => _picking;

  /// The slot [picking] came from.
  int? get pickingSlot => _pickingSlot;

  /// Whether a slot is armed or a picker is open: presses on the green
  /// belong to the targeting, not to the aim.
  bool get isActive => _armed != null || _picking != null;

  /// Where the pointer is over the green while a slot is armed: the spot
  /// the reticle marks. Null while the pointer is off the green.
  Vec2? get hover => _hover;

  set hover(Vec2? value) {
    if (_armed == null) value = null;
    if (value == _hover) return;
    _hover = value;
    notifyListeners();
  }

  /// A short line for the hint strip when a tap could not arm (no egg of
  /// mine to hop, no other egg to hit), and its serial: the same line
  /// twice still shows twice.
  String? get notice => _notice;
  int get noticeSerial => _noticeSerial;

  /// A slot was tapped: casts, arms, opens the picker, or - the same slot
  /// tapped twice - cancels.
  void tapSlot(PuttMatch match, int slot, String effectId) {
    if (!canUseNow(match)) return;
    switch (puttPowerAimOf(effectId)) {
      case PuttPowerAim.none:
        _clear();
        notifyListeners();
        _cast(match, effectId, null);
      case PuttPowerAim.point:
        if (_armed == effectId && _armedSlot == slot) {
          cancel();
          return;
        }
        final blocked = pointBlocker(match, effectId);
        _clear();
        if (blocked != null) {
          _notice = blocked;
          _noticeSerial++;
        } else {
          _armed = effectId;
          _armedSlot = slot;
        }
        notifyListeners();
      case PuttPowerAim.player:
        if (_picking == effectId && _pickingSlot == slot) {
          cancel();
          return;
        }
        _clear();
        _picking = effectId;
        _pickingSlot = slot;
        notifyListeners();
    }
  }

  /// The armed effect, cast at [point]. False (and nothing spent) when no
  /// slot is armed or the cast no longer makes sense.
  bool castAt(PuttMatch match, Vec2 point) {
    final effectId = _armed;
    if (effectId == null) return false;
    if (!canUseNow(match) || pointBlocker(match, effectId) != null) {
      cancel();
      return false;
    }
    _clear();
    notifyListeners();
    return _cast(match, effectId, PowerUpTarget.point(point));
  }

  /// The picker's effect, cast on [playerId]. False (and nothing spent)
  /// when no picker is open or [playerId] cannot be picked.
  bool castOn(PuttMatch match, String playerId) {
    final effectId = _picking;
    if (effectId == null) return false;
    if (!canUseNow(match) || !candidates(match, effectId).contains(playerId)) {
      return false;
    }
    _clear();
    notifyListeners();
    return _cast(match, effectId, PowerUpTarget.player(playerId));
  }

  bool _cast(PuttMatch match, String effectId, PowerUpTarget? target) {
    final before = match.myBall?.position;
    final cast = match.usePowerUp(effectId, target);
    if (cast) onCast?.call(effectId, target, before);
    return cast;
  }

  /// Drops the armed slot or the open picker, spending nothing.
  void cancel() {
    if (!isActive) return;
    _clear();
    notifyListeners();
  }

  /// Once a frame: lets go of a targeting the match no longer allows (the
  /// hole ended, a crow took the power-up, I went to watch) and follows
  /// the slot when the inventory shifted under it.
  void validate(PuttMatch match) {
    final effectId = _armed ?? _picking;
    if (effectId == null) return;
    final inventory = match.myInventory;
    if (!canUseNow(match) || !inventory.contains(effectId)) {
      cancel();
      return;
    }
    // An armed spot effect that can no longer do anything (my egg went in,
    // the others all did) lets go too.
    if (_armed != null && pointBlocker(match, effectId) != null) {
      cancel();
      return;
    }
    final slot = (_armed != null ? _armedSlot : _pickingSlot) ?? -1;
    if (slot < 0 || slot >= inventory.length || inventory[slot] != effectId) {
      final moved = inventory.indexOf(effectId);
      if (_armed != null) {
        _armedSlot = moved;
      } else {
        _pickingSlot = moved;
      }
      notifyListeners();
    }
  }

  void _clear() {
    _armed = null;
    _armedSlot = null;
    _picking = null;
    _pickingSlot = null;
    _hover = null;
    _notice = null;
  }

  /// Whether power-ups can be used at all right now: a hole in play, and
  /// me on the green rather than watching.
  static bool canUseNow(PuttMatch match) =>
      match.phase == PuttPhase.holePlay &&
      !match.isSpectator &&
      match.localPlayer != null;

  /// Why a point effect would do nothing right now, or null when it can
  /// go: a Rabbit Hole needs my egg out on the green, a Gust or a
  /// Sprinkler another egg to push.
  static String? pointBlocker(PuttMatch match, String effectId) {
    switch (effectId) {
      case 'rabbit_hole':
        final mine = match.myBall;
        if (mine == null || mine.holed) return messagePuttEggInNest();
        return null;
      case 'gust':
      case 'sprinkler':
        if (otherEggs(match).isEmpty) return messagePuttNoEggsToPush();
        return null;
      default:
        return null;
    }
  }

  /// The players a player effect can go to right now, in seat order: a
  /// Nest Swap trades with an egg still on the green (mine too must be
  /// out there), a Thieving Crow robs someone holding a power-up.
  static List<String> candidates(PuttMatch match, String effectId) {
    final me = match.localPlayerId;
    switch (effectId) {
      case 'nest_swap':
        final mine = match.myBall;
        if (mine == null || mine.holed) return const [];
        return [
          for (final ball in otherEggs(match)) ball.playerId,
        ];
      case 'thieving_crow':
        return [
          for (final player in match.engine.players)
            if (player.id != me &&
                !player.spectator &&
                !player.inventory.isEmpty)
              player.id,
        ];
      default:
        return const [];
    }
  }

  /// Why the picker for [effectId] has nobody to list.
  static String nobodyToPick(PuttMatch match, String effectId) {
    if (effectId == 'nest_swap') {
      final mine = match.myBall;
      if (mine == null || mine.holed) return messagePuttEggInNest();
      return messagePuttNobodyToSwap();
    }
    return messagePuttNobodyToRob();
  }

  /// The other eggs still out on the green.
  static List<BallView> otherEggs(PuttMatch match) {
    final world = match.engine.world;
    if (world == null) return const [];
    return [
      for (final ball in world.balls)
        if (ball.playerId != match.localPlayerId && !ball.holed)
          BallView(
            playerId: ball.playerId,
            position: ball.position,
            velocity: ball.velocity,
            holed: ball.holed,
          ),
    ];
  }
}

// ---- strings -------------------------------------------------------------------

/// The hint line while a point effect waits for its spot.
String labelPuttTargetPrompt(String effectId) {
  switch (effectId) {
    case 'rabbit_hole':
      return labelPuttTargetRabbitHole();
    case 'gust':
      return labelPuttTargetGust();
    case 'sprinkler':
      return labelPuttTargetSprinkler();
    default:
      return labelPuttTargetSpot();
  }
}

String labelPuttTargetRabbitHole() =>
    Intl.message("Tap a spot to hop your egg there",
        name: "labelPuttTargetRabbitHole",
        desc: "Hint line while the Rabbit Hole power-up waits for the spot "
            "on the green the player's egg pops up at (a few steps away at "
            "most)");

String labelPuttTargetGust() =>
    Intl.message("Tap a spot: the wind blows the other eggs toward it",
        name: "labelPuttTargetGust",
        desc: "Hint line while the Gust power-up waits for its spot on the "
            "green; every other player's egg is pushed toward it");

String labelPuttTargetSprinkler() =>
    Intl.message("Tap a spot: the sprinkler soaks the eggs around it",
        name: "labelPuttTargetSprinkler",
        desc: "Hint line while the Sprinkler power-up waits for its spot on "
            "the green; the other eggs near it are pushed away");

String labelPuttTargetSpot() => Intl.message("Pick a spot on the green",
    name: "labelPuttTargetSpot",
    desc: "Hint line while a power-up waits for the spot on the green it "
        "acts on");

String labelPuttTargetCancel() =>
    Intl.message("Tap the power-up again to cancel",
        name: "labelPuttTargetCancel",
        desc: "Under the targeting hint: tapping the glowing power-up slot "
            "a second time puts it away unused");

String messagePuttEggInNest() => Intl.message("Your egg is already in the nest",
    name: "messagePuttEggInNest",
    desc: "Why a power-up that moves the player's own egg cannot be used: "
        "the egg already finished the hole");

String messagePuttNoEggsToPush() =>
    Intl.message("No other eggs on the green to push",
        name: "messagePuttNoEggsToPush",
        desc: "Why the Gust or Sprinkler power-up cannot be used: every "
            "other egg is already in the nest");

String messagePuttNobodyToSwap() =>
    Intl.message("Nobody on the green to swap with",
        name: "messagePuttNobodyToSwap",
        desc: "The Nest Swap picker when no other player's egg is still on "
            "the green; the power-up is kept");

String messagePuttNobodyToRob() =>
    Intl.message("Nobody has a power-up to steal",
        name: "messagePuttNobodyToRob",
        desc: "The Thieving Crow picker when no other player holds a "
            "power-up; the crow is kept");

String labelPuttPickSwap() => Intl.message("Swap places with…",
    name: "labelPuttPickSwap",
    desc: "Title of the Nest Swap picker, over the list of players whose "
        "egg the player's own egg can trade places with");

String labelPuttPickSteal() => Intl.message("Steal a power-up from…",
    name: "labelPuttPickSteal",
    desc: "Title of the Thieving Crow picker, over the list of players "
        "holding a power-up the crow can take");
