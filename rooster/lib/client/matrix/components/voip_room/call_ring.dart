// Someone starting a room's call can ring the others (MSC4075:
// `org.matrix.msc4075.rtc.notification`, `m.call.notify` before it), and
// whoever is rung can decline (MSC4310: `m.rtc.decline`,
// `org.matrix.msc4310.rtc.decline` while unstable). Pure Dart, the same on
// every platform. See docs/voice-channel-members.md, "Ringing".
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/debug/log.dart';

/// A call ringing us: the notification that rings, from whom, until when
/// (by the homeserver's clock).
class CallRing {
  const CallRing(
      {required this.eventId, required this.senderId, required this.endsAt});

  final String eventId;
  final String senderId;
  final DateTime endsAt;
}

class CallRings {
  CallRings(this.room, {required DateTime Function() now}) : _now = now;

  final matrix.Room room;

  /// The homeserver's time: a notification rings for its lifetime by it.
  final DateTime Function() _now;

  static const notifyTypes = {
    matrix.RtcNotificationContent.eventType,
    "m.rtc.notification",
    "m.call.notify",
    "org.matrix.msc4075.call.notify",
  };

  static const stableDeclineType = "m.rtc.decline";
  static const unstableDeclineType = "org.matrix.msc4310.rtc.decline";
  static const declineTypes = {stableDeclineType, unstableDeclineType};

  /// Every event type [receive] acts on.
  static const types = {...notifyTypes, ...declineTypes};

  /// The call ringing us now, or null.
  final ValueNotifier<CallRing?> ringing = ValueNotifier(null);

  Timer? _end;

  /// Until when [event] rings us at [now], or null when it does not: not a
  /// ring (a plain notification), ours, for others, or over. It rings for
  /// its `lifetime` (30 s by default, two minutes at most) from when it was
  /// sent: its `sender_ts`, unless that is far from the homeserver's.
  static DateTime? ringsUntil(matrix.Event event,
      {required String ownUserId, required DateTime now}) {
    if (!notifyTypes.contains(event.type)) return null;
    if (event.senderId == ownUserId) return null;
    final content = event.content;
    final kind = content["notification_type"] ?? content["notify_type"];
    if (kind != "ring") return null;
    if (content["m.mentions"] is Map) {
      final mentions = event.mentions;
      if (!mentions.room && !mentions.userIds.contains(ownUserId)) {
        return null;
      }
    }
    final senderTs = content["sender_ts"];
    final lifetime = content["lifetime"];
    final ring = matrix.RtcNotificationContent(
      senderTs: senderTs is int
          ? DateTime.fromMillisecondsSinceEpoch(senderTs)
          : event.originServerTs,
      notificationType: matrix.RtcNotificationType.ring,
      lifetime: lifetime is int
          ? Duration(milliseconds: lifetime)
          : matrix.RtcNotificationContent.defaultLifetime,
    );
    final endsAt = ring
        .getEffectiveTimestamp(event.originServerTs)
        .add(ring.cappedLifetime);
    return endsAt.isAfter(now) ? endsAt : null;
  }

  /// A notification or a decline arrived in the room. A ring starts
  /// ringing, replacing one already ringing; our decline from another
  /// device stops the ring it declines.
  void receive(matrix.Event event) {
    final ownUserId = room.client.userID;
    if (ownUserId == null) return;
    if (declineTypes.contains(event.type)) {
      if (event.senderId == ownUserId &&
          event.relationshipEventId == ringing.value?.eventId) {
        _stop();
      }
      return;
    }
    final now = _now();
    final endsAt = ringsUntil(event, ownUserId: ownUserId, now: now);
    if (endsAt == null) return;
    _end?.cancel();
    ringing.value = CallRing(
        eventId: event.eventId, senderId: event.senderId, endsAt: endsAt);
    _end = Timer(endsAt.difference(now), _stop);
  }

  /// We joined the call: it rings no more.
  void answered() => _stop();

  /// Declines the call ringing us: it stops ringing at once, and the room
  /// hears of it with a decline that references the notification.
  Future<void> decline() async {
    final ring = ringing.value;
    if (ring == null) return;
    _stop();
    try {
      await room.sendEvent({
        "m.relates_to": {"rel_type": "m.reference", "event_id": ring.eventId},
      }, type: await _declineType());
    } catch (e, s) {
      Log.onError(e, s, content: "Could not decline the call");
    }
  }

  /// The stable type from Matrix v1.20 (or with its flag), else the
  /// unstable one other clients read today.
  Future<String> _declineType() async {
    try {
      final versions = await room.client.getVersions();
      if (versions.unstableFeatures?["org.matrix.msc4310.stable"] == true ||
          versions.versions.any(_fromV120)) {
        return stableDeclineType;
      }
    } catch (e) {
      Log.w("Could not read the homeserver's versions: $e");
    }
    return unstableDeclineType;
  }

  static bool _fromV120(String version) {
    final match = RegExp(r"^v(\d+)\.(\d+)").firstMatch(version);
    if (match == null) return false;
    final major = int.parse(match[1]!), minor = int.parse(match[2]!);
    return major > 1 || (major == 1 && minor >= 20);
  }

  void _stop() {
    _end?.cancel();
    _end = null;
    ringing.value = null;
  }

  void dispose() {
    _end?.cancel();
    ringing.dispose();
  }
}
