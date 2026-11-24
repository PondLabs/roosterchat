// Who is in a room's call, from every MatrixRTC membership format at once:
// the legacy state event (`org.matrix.msc3401.call.member`, what Rooster
// writes with its badges and delayed leave), and the newer `m.rtc.member`
// (`org.matrix.msc4143.rtc.member` while unstable, MSC4143), in room state
// or as a sticky event (MSC4354). One membership per person's device, so a
// client that writes both formats is listed once. Whether one has lapsed is
// for the caller to say, by the homeserver's clock. See
// docs/voice-channel-members.md, "Newer MatrixRTC clients".
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/matrix_call_membership.dart';

class CallMemberships {
  /// The legacy membership, one state event per device.
  static const legacyType = "org.matrix.msc3401.call.member";

  /// Every event type a membership comes in.
  static const types = {legacyType, ...matrix.RtcMemberships.types};

  /// The type our own membership goes out in the newer format as, a sticky
  /// event (MSC4354) where the homeserver has them.
  static const stickyType = matrix.RtcMemberships.unstableType;

  /// Our membership in the newer format, from [legacy], our legacy one:
  /// the same call, device and foci. [stickyKey] is what a later one
  /// replaces it by.
  static Map<String, Object?> stickyContent(Map<String, Object?> legacy,
          {required String userId,
          required String deviceId,
          required String stickyKey}) =>
      {
        "slot_id": "m.call#",
        "application": {"type": "m.call", "m.call.id": legacy["call_id"] ?? ""},
        "member": {"id": deviceId, "user_id": userId, "device_id": deviceId},
        "rtc_transports": legacy["foci_preferred"] ?? const [],
        "versions": const [],
        "msc4354_sticky_key": stickyKey,
      };

  /// Leaves the membership [stickyKey] names: no application, and the
  /// member, so a reader that also has our legacy membership knows which
  /// device left. A leave without it replaces the join it shares a sticky
  /// key with, and says nothing about the legacy one.
  static Map<String, Object?> stickyLeave(String stickyKey,
          {required String userId, required String deviceId}) =>
      {
        "member": {"id": deviceId, "user_id": userId, "device_id": deviceId},
        "msc4354_sticky_key": stickyKey,
      };

  /// Whether [update] brings a membership of any format: the list of who is
  /// in the call has to be worked out again.
  static bool touches(matrix.JoinedRoomUpdate update) => [
        ...?update.state,
        ...?update.stateAfter,
        ...?update.timeline?.events,
        ...?update.sticky,
      ].any((event) => types.contains(event.type));

  /// The memberships in [room] that count at [now], once per application
  /// on a person's device (the call, or a widget's activity: a device in
  /// the call that also runs an activity is in both), each as a legacy
  /// membership: its content in the legacy shape, the newer format's turned
  /// into it (application, call id, device, `expires` from when it was
  /// sent, foci). The legacy one of a device is the one kept while both
  /// formats say it is in the call: only it has Rooster's badges, and a
  /// delayed leave behind it. Otherwise the newer says, unless one has only
  /// lapsed: a legacy membership the delayed leave cleared takes down an
  /// older sticky one of the same device, a sticky one that lapsed does not
  /// take down a live legacy one.
  ///
  /// Lapsed memberships are left in: callers skip them, and log it.
  static List<matrix.StrippedStateEvent> of(matrix.Room room,
      {required DateTime now}) {
    // By (person, device, application).
    final bySlot = <(String, String, String), matrix.StrippedStateEvent>{};

    void offer(matrix.StrippedStateEvent membership,
        ({String deviceId, String application}) slot) {
      final key = (membership.senderId, slot.deviceId, slot.application);
      final kept = bySlot[key];
      if (kept == null || _prefer(membership, kept: kept, now: now)) {
        bySlot[key] = membership;
      }
    }

    final legacy = room.states[legacyType] ?? const {};
    for (final entry in legacy.entries) {
      offer(entry.value, _legacySlotOf(entry.value, entry.key));
    }
    for (final event in matrix.RtcMemberships.eventsOf(room)) {
      final deviceId = matrix.RtcMemberships.deviceIdOf(event.content);
      if (deviceId == null) continue;
      final application = _newerApplicationOf(event.content);
      offer(_asLegacy(event, room, deviceId, application),
          (deviceId: deviceId, application: application));
    }
    return bySlot.values.toList();
  }

  static DateTime? _sentAt(matrix.StrippedStateEvent e) =>
      e is matrix.Event ? e.originServerTs : null;

  static bool _isLegacy(matrix.StrippedStateEvent e) =>
      e is! matrix.Event || e.unsigned?[_formatKey] == null;

  static bool _left(matrix.StrippedStateEvent e) =>
      e.content['application'] == null;

  static bool _lapsed(matrix.StrippedStateEvent e, DateTime now) =>
      !_left(e) && MatrixCallMembership.isExpired(e.content, _sentAt(e), now);

  /// Whether [candidate] tells more truly than [kept] whether its device is
  /// in the call (see [of]).
  static bool _prefer(matrix.StrippedStateEvent candidate,
      {required matrix.StrippedStateEvent kept, required DateTime now}) {
    final candidateIn = !_left(candidate) && !_lapsed(candidate, now);
    final keptIn = !_left(kept) && !_lapsed(kept, now);
    if (candidateIn && keptIn) return _isLegacy(candidate) && !_isLegacy(kept);
    if (_lapsed(candidate, now) && keptIn) return false;
    if (_lapsed(kept, now) && candidateIn) return true;
    final a = _sentAt(candidate), b = _sentAt(kept);
    if (a == null || b == null || a == b) {
      return _isLegacy(candidate) && !_isLegacy(kept);
    }
    return a.isAfter(b);
  }

  /// The device and application of a legacy membership. A cleared one is
  /// empty: they are in its state key,
  /// `_<user id>_<device id>_<application>`. A state key of another shape
  /// is a membership of its own.
  static ({String deviceId, String application}) _legacySlotOf(
      matrix.StrippedStateEvent event, String stateKey) {
    String? fromKey(bool application) {
      final prefix = '_${event.senderId}_';
      if (!stateKey.startsWith(prefix)) return null;
      final rest = stateKey.substring(prefix.length);
      final end = rest.lastIndexOf('_');
      if (end <= 0) return null;
      return application ? rest.substring(end + 1) : rest.substring(0, end);
    }

    final device = event.content['device_id'];
    final application = event.content['application'];
    return (
      deviceId: device is String ? device : fromKey(false) ?? stateKey,
      application:
          application is String ? application : fromKey(true) ?? stateKey,
    );
  }

  /// The application of a membership of the newer format. One that has
  /// left names none: it is its slot's (`m.call#...`), or the call.
  static String _newerApplicationOf(Map<String, Object?> content) {
    final application = matrix.RtcMemberships.applicationOf(content);
    if (application != null) return application;
    final slot = content['slot_id'];
    final end = slot is String ? slot.indexOf('#') : -1;
    return end > 0 ? (slot as String).substring(0, end) : 'm.call';
  }

  /// Marks a membership turned into the legacy shape, in its `unsigned`.
  static const _formatKey = 'chat.commet.membership_format';

  /// [event], a membership of the newer format of [deviceId] in [slot]
  /// (an application), as a legacy one (see [of]).
  static matrix.Event _asLegacy(
      matrix.Event event, matrix.Room room, String deviceId, String slot) {
    final content = event.content;
    final application = matrix.RtcMemberships.applicationOf(content);
    final sentAt = event.originServerTs;
    return matrix.Event(
      type: legacyType,
      senderId: event.senderId,
      stateKey: '_${event.senderId}_${deviceId}_$slot',
      eventId: event.eventId,
      originServerTs: sentAt,
      unsigned: {_formatKey: event.type},
      room: room,
      content: {
        if (application != null) ...{
          'application': application,
          'call_id': matrix.RtcMemberships.callIdOf(content),
          'device_id': deviceId,
          'scope': 'm.room',
          'expires': matrix.RtcMemberships.expiresAt(event)
              .difference(sentAt)
              .inMilliseconds,
          'foci_preferred': matrix.RtcMemberships.transportsOf(content),
        },
      },
    );
  }
}
