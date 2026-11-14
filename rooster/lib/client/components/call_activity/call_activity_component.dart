// The call-activities framework's contracts: what an activity is, the typed
// registry, the lifecycle roles, and the room-state hook the Matrix layer
// implements. No Matrix, no LiveKit; Flutter only for the types of the
// stage hooks, which live in call_activity_controller.dart (dj_engine.dart
// is the precedent for the shape, soundboard_event.dart for the style).
//
// A call activity is a game played inside a voice call. The caller launches
// it; everyone in the call sees it, joins it as a player or watches as a
// spectator. The session itself lives in call_activity_session.dart, the
// wire format in call_activity_protocol.dart. The call view knows no game:
// everything it shows of one comes from the descriptor's hooks below.
import 'package:flutter/widgets.dart' show BuildContext;

import 'call_activity_controller.dart';

export 'call_activity_controller.dart';

/// A role in an activity session.
///
/// Exactly one [CallActivitySession] client is the [CallActivityRole.host]
/// and owns the session's state; everyone else either plays
/// ([CallActivityRole.player]) or watches ([CallActivityRole.spectator]).
enum CallActivityRole {
  host,
  player,
  spectator;

  /// The value sent on the wire in `join` messages: [name] in English,
  /// lowercased, like the DJ protocol's small values.
  String get wire => name.toLowerCase();

  /// Parses back [wire].
  static CallActivityRole? parse(Object? value) => switch (value) {
        'host' => host,
        'player' => player,
        'spectator' => spectator,
        _ => null,
      };
}

/// The life of a session, as the room state and the wire see it.
enum CallActivityStage {
  /// Someone has launched it; players can join.
  open,

  /// The host ended it (left the call or closed the activity).
  closed,
}

/// Whether this device can run an activity, and why not when it cannot.
class CallActivityAvailability {
  /// This device runs it.
  const CallActivityAvailability.available()
      : reason = null,
        _available = true;

  /// This device does not run it (a game that needs face tracking where
  /// there is none). [reason] says why, in the app's language; without one
  /// the shelf and the invite say it is not available on this device.
  const CallActivityAvailability.unavailable([this.reason])
      : _available = false;

  final bool _available;

  /// Why it is unavailable, resolved when shown; null for the generic
  /// sentence (and always null when available).
  final String Function()? reason;

  bool get isAvailable => _available;
}

CallActivityAvailability _alwaysAvailable() =>
    const CallActivityAvailability.available();

/// One activity: what the pickers show, what the room state and the
/// protocol name by [id], and the hooks the call's stage runs it through.
///
/// A game registers one of these in [CallActivityRegistry] at startup
/// (main.dart). The call view then lists it on the shelf, asks
/// [launchOptions] and [createController] when someone launches it, and
/// puts the controller's view on the stage, under [displayName].
class CallActivity {
  /// The event type of the session's room state and the session's id in the
  /// protocol. Namespaced like every event type (ADR-0003), e.g.
  /// `chat.commet.putt`.
  final String id;

  /// The display name, resolved when shown so translations are picked up
  /// late. Titles proper are kept in English by the descriptor's caller
  /// (the game title is not translated).
  final String Function() displayName;

  /// The icon in pickers and room rows. The contracts hold no Flutter
  /// imports, so this is opaque here: the app layer stores an `ImageOrIcon`
  /// (typed where it is built), tests stub anything.
  final Object? Function()? icon;

  /// Fewest players a match makes sense with; one: a lone player.
  final int minPlayers;

  /// Most players allowed; spec puts it at 8 and the ninth joins a
  /// spectator queue.
  final int maxPlayers;

  /// Asks the launcher how to play (a mode, a course), before anything is
  /// written: the value goes to [CallActivityController.hostStart]. Null
  /// from it means the launcher backed out, and nothing launches. Absent:
  /// the activity launches straight away, with null options.
  final Future<Object?> Function(BuildContext context)? launchOptions;

  /// Builds this client's controller of a session: when we launch it (then
  /// [CallActivityController.hostStart] runs), join it, or come back to it
  /// with the call's view. Every playable game has one; a descriptor
  /// without it only names an activity (the room list's badges), and
  /// launching or joining it fails.
  final CallActivityController Function(CallActivityCallContext call)?
      createController;

  /// The game draws the players' videos itself (from
  /// [CallActivityCallContext.cameraOf]): the stage's strip of the call's
  /// videos then shows only the people who do not play. False: the strip
  /// shows everyone, as for Sunny Side Putt.
  final bool drawsPlayerVideos;

  /// Whether this device can run the activity, asked each time the shelf
  /// or the invite is shown. An unavailable activity cannot be launched or
  /// joined here; both say why instead of offering it.
  final CallActivityAvailability Function() availability;

  const CallActivity({
    required this.id,
    required this.displayName,
    this.icon,
    this.minPlayers = 1,
    this.maxPlayers = 8,
    this.launchOptions,
    this.createController,
    this.drawsPlayerVideos = false,
    this.availability = _alwaysAvailable,
  });
}

/// The typed registry of activities. Every game registers its descriptor
/// here. Entries are keyed by [CallActivity.id]:
/// registering the same id again replaces the old entry, so a stub can be
/// swapped for the real one.
class CallActivityRegistry {
  CallActivityRegistry._();

  static final Map<String, CallActivity> _byId = {};

  /// Everything registered, registry order.
  static List<CallActivity> get all => List.unmodifiable(_byId.values);

  static CallActivity? byId(String id) => _byId[id];

  /// Adds [activity], or replaces the entry with the same id. Returns the
  /// registered entry.
  static CallActivity register(CallActivity activity) {
    _byId[activity.id] = activity;
    return activity;
  }

  /// Removes the entry with [id]; whether there was one. For tests and
  /// retirings.
  static bool remove(String id) => _byId.remove(id) != null;

  /// Empties the registry. For tests.
  static void clear() => _byId.clear();
}

/// The session's room state: the `chat.commet.call_activity` event that
/// makes a session visible to people outside the call. One event per
/// session, its state key the session id; content: the [activityId], the
/// [hostUserId] who launched it, [createdAtMs] (written from the
/// homeserver's clock see HomeserverClock) and the `expires` window in
/// milliseconds after [createdAtMs] that ends it, like a call membership's.
/// A session whose state is gone or expired is over; the Matrix
/// implementation drops the visible one when that happens.
abstract class CallActivityRoomState {
  /// Writes (or rewrites) the state event of [sessionId].
  Future<void> write({
    required String sessionId,
    required String activityId,
    required String hostUserId,
    required int createdAtMs,
  });

  /// Clears the state event of [sessionId]: the session is over.
  Future<void> clear(String sessionId);
}
