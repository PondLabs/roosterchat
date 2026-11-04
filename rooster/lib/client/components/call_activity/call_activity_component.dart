// The call-activities framework's contracts: what an activity is, the typed
// registry, the lifecycle roles, and the room-state hook the Matrix layer
// implements. Pure Dart - no Flutter, no Matrix, no LiveKit - so the session
// logic stays testable headless (dj_engine.dart is the precedent for the
// shape, soundboard_event.dart for the style).
//
// A call activity is a game (today Sunny Side Putt) played inside a voice
// call. The caller launches it; everyone in the call sees it, joins it as a
// player or watches as a spectator. The session itself lives in
// call_activity_session.dart, the wire format in call_activity_protocol.dart.

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

/// One activity: what the pickers show, what the room state and the
/// protocol name by [id].
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

  const CallActivity({
    required this.id,
    required this.displayName,
    this.icon,
    this.minPlayers = 1,
    this.maxPlayers = 8,
  });
}

/// The typed registry of activities. One entry today; games from other
/// tickets register theirs here. Entries are keyed by [CallActivity.id]:
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
