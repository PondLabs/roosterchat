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

  /// The memberships in [room] that count at [now], once per person's
  /// device, each as a legacy membership: its content in the legacy shape,
  /// the newer format's turned into it (application, call id, device,
  /// `expires` from when it was sent, foci). The legacy one of a device is
  /// the one kept while both formats say it is in the call: only it has
  /// Rooster's badges, and a delayed leave behind it. Otherwise the newer
  /// says, unless one has only lapsed: a legacy membership the delayed leave
  /// cleared takes down an older sticky one of the same device, a sticky one
  /// that lapsed does not take down a live legacy one.
  ///
  /// Lapsed memberships are left in: callers skip them, and log it.
  static List<matrix.StrippedStateEvent> of(matrix.Room room,
      {required DateTime now}) {
    final byDevice = <(String, String), matrix.StrippedStateEvent>{};
    final rest = <matrix.StrippedStateEvent>[];

    void offer(matrix.StrippedStateEvent membership, String? deviceId) {
      if (deviceId == null) {
        rest.add(membership);
        return;
      }
      final key = (membership.senderId, deviceId);
      final kept = byDevice[key];
      if (kept == null || _prefer(membership, kept: kept, now: now)) {
        byDevice[key] = membership;
      }
    }

    final legacy = room.states[legacyType] ?? const {};
    for (final entry in legacy.entries) {
      offer(entry.value,
          _legacyDeviceOf(entry.value, entry.key) ?? entry.value.stateKey);
    }
    for (final event in matrix.RtcMemberships.eventsOf(room)) {
      final membership = _asLegacy(event, room);
      if (membership != null) {
        offer(membership, matrix.RtcMemberships.deviceIdOf(event.content));
      }
    }
    return [...byDevice.values, ...rest];
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

  /// A cleared legacy membership is empty: its device is in its state key,
  /// `_<user id>_<device id>_<application>`.
  static String? _legacyDeviceOf(
      matrix.StrippedStateEvent event, String stateKey) {
    final device = event.content['device_id'];
    if (device is String) return device;
    final prefix = '_${event.senderId}_';
    if (!stateKey.startsWith(prefix)) return null;
    final rest = stateKey.substring(prefix.length);
    final end = rest.lastIndexOf('_');
    return end > 0 ? rest.substring(0, end) : null;
  }

  /// Marks a membership turned into the legacy shape, in its `unsigned`.
  static const _formatKey = 'chat.commet.membership_format';

  /// [event], a membership of the newer format, as a legacy one (see
  /// [of]); null for one that carries no device.
  static matrix.Event? _asLegacy(matrix.Event event, matrix.Room room) {
    final content = event.content;
    final deviceId = matrix.RtcMemberships.deviceIdOf(content);
    if (deviceId == null) return null;
    final application = matrix.RtcMemberships.applicationOf(content);
    final sentAt = event.originServerTs;
    return matrix.Event(
      type: legacyType,
      senderId: event.senderId,
      stateKey: '_${event.senderId}_${deviceId}_m.call',
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
