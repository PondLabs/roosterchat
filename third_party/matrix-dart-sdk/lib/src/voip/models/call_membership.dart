import 'package:matrix/matrix.dart';

class FamedlyCallMemberEvent {
  final List<CallMembership> memberships;

  FamedlyCallMemberEvent({required this.memberships});

  Map<String, dynamic> toJson() {
    return {'memberships': memberships.map((e) => e.toJson()).toList()};
  }

  factory FamedlyCallMemberEvent.fromJson(Event event, VoIP voip) {
    final List<CallMembership> callMemberships = [];
    final memberships = event.content.tryGetList('memberships');
    if (memberships != null && memberships.isNotEmpty) {
      for (final mem in memberships) {
        if (isValidMemEvent(mem)) {
          final callMem = CallMembership.fromJson(
            mem,
            event.senderId,
            event.room.id,
            event.eventId,
            voip,
          );
          if (callMem != null) callMemberships.add(callMem);
        }
      }
    }
    return FamedlyCallMemberEvent(memberships: callMemberships);
  }
}

/// userId - The userId of the member
///
/// callId - The callId the member is a part of, usually an empty string
///
/// application, scope - something you can narrow down the calls with, might be
/// removed soon
///
/// backend - The CallBackend, either mesh or livekit
///
/// deviceId - The deviceId of the member
///
/// eventId - The eventId in matrix for this call membership
/// not always present because we do not have it when we are just sending
/// the event
///
/// expiresTs - Timestamp at which this membership event will be considered expired
///
/// membershipId - A cachebuster for state events, usually is reset every time a client
/// loads
///
/// feeds - Feeds from mesh calls, is not used for livekit calls
///
/// voip - The voip parent class for using timeouts probably
///
/// roomId - The roomId for the call
class CallMembership {
  final String userId;
  final String callId;
  final String? application;
  final String? scope;
  final CallBackend backend;
  final String deviceId;
  final String? eventId;
  final int expiresTs;
  final String membershipId;
  final List? feeds;
  final VoIP voip;
  final String roomId;

  CallMembership({
    required this.userId,
    required this.callId,
    required this.backend,
    required this.deviceId,
    this.eventId,
    required this.expiresTs,
    required this.roomId,
    required this.membershipId,
    required this.voip,
    this.application = 'm.call',
    this.scope = 'm.room',
    this.feeds,
  });

  Map<String, dynamic> toJson() {
    return {
      'call_id': callId,
      'application': application,
      'scope': scope,
      'foci_active': [backend.toJson()],
      'device_id': deviceId,
      'expires_ts': expiresTs,
      'membershipID': membershipId, // sessionId
      if (feeds != null) 'feeds': feeds,
    };
  }

  static CallMembership? fromJson(
    Map json,
    String userId,
    String roomId,
    String? eventId,
    VoIP voip,
  ) {
    try {
      return CallMembership(
        userId: userId,
        roomId: roomId,
        callId: json['call_id'],
        application: json['application'],
        scope: json['scope'],
        backend: (json['foci_active'] as List)
            .map((e) => CallBackend.fromJson(e))
            .first,
        deviceId: json['device_id'],
        eventId: eventId,
        expiresTs: json['expires_ts'],
        membershipId:
            json['membershipID'] ?? 'someone_forgot_to_set_the_membershipID',
        feeds: json['feeds'],
        voip: voip,
      );
    } catch (e, s) {
      Logs().e('[VOIP] call membership parsing failed. $json', e, s);
      return null;
    }
  }

  @override
  bool operator ==(other) =>
      identical(this, other) ||
      other is CallMembership &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          roomId == other.roomId &&
          callId == other.callId &&
          application == other.application &&
          scope == other.scope &&
          backend.type == other.backend.type &&
          deviceId == other.deviceId &&
          eventId == other.eventId &&
          membershipId == other.membershipId;

  @override
  int get hashCode => Object.hash(
        userId.hashCode,
        roomId.hashCode,
        callId.hashCode,
        application.hashCode,
        scope.hashCode,
        backend.type.hashCode,
        deviceId.hashCode,
        eventId.hashCode,
        membershipId.hashCode,
      );

  // with a buffer of 1 minute just incase we were slow to process a
  // call event, if the device is actually dead it should
  // get removed pretty soon
  bool get isExpired =>
      expiresTs <
      DateTime.now()
          .subtract(voip.timeouts!.expireTsBumpDuration)
          .millisecondsSinceEpoch;

  @override
  String toString() {
    return 'CallMembership(userId: $userId, callId: $callId, application: $application, scope: $scope, backend: $backend, deviceId: $deviceId, eventId: $eventId, expiresTs: $expiresTs, membershipId: $membershipId, feeds: $feeds, voip: $voip, roomId: $roomId)';
  }
}

// ROOSTER: A membership of the newer MatrixRTC format (MSC4143, T5.2):
// `m.rtc.member`, `org.matrix.msc4143.rtc.member` while unstable, one per
// device, in room state or as a sticky event (MSC4354); its content is
// [RtcMemberContent]. Its `application`
// is an object (`{"type": "m.call", ...}`), the device is in `member`, the
// foci are `rtc_transports`, and one without `application` has left.
class RtcMemberships {
  static const stableType = EventTypes.RtcMember;
  static const unstableType = 'org.matrix.msc4143.rtc.member';
  static const types = {stableType, unstableType};

  /// How long a state membership without `expires` counts, MatrixRTC's
  /// default window. A sticky one counts while it is sticky.
  static const defaultLifetime = Duration(hours: 4);

  /// The application's type (`m.call`), or null for one that has left.
  static String? applicationOf(Map<String, Object?> content) {
    final application = content['application'];
    if (application is Map && application['type'] is String) {
      return application['type'] as String;
    }
    return application is String ? application : null;
  }

  static String callIdOf(Map<String, Object?> content) {
    final application = content['application'];
    final id = application is Map
        ? application['m.call.id'] ?? application['call_id']
        : content['call_id'];
    return id is String ? id : '';
  }

  static String? deviceIdOf(Map<String, Object?> content) {
    final member = content['member'];
    final id = member is Map
        ? member['device_id'] ?? member['claimed_device_id']
        : content['device_id'];
    return id is String ? id : null;
  }

  static String? memberIdOf(Map<String, Object?> content) {
    final member = content['member'];
    final id = member is Map ? member['id'] : null;
    return id is String ? id : null;
  }

  static List<Map<String, Object?>> transportsOf(Map<String, Object?> content) {
    final transports = content['rtc_transports'] ?? content['foci_preferred'];
    return [
      if (transports is List)
        for (final t in transports)
          if (t is Map) Map<String, Object?>.from(t),
    ];
  }

  /// When [event]'s membership stops counting: when it stops being sticky,
  /// else `expires` (or [defaultLifetime]) after it was sent.
  static DateTime expiresAt(Event event) {
    final sticky = RoomStickyEvents.stickyExpiresAt(event);
    if (sticky != null) return sticky;
    final expires = event.content['expires'];
    return event.originServerTs.add(
      expires is int ? Duration(milliseconds: expires) : defaultLifetime,
    );
  }

  /// The memberships of this format in [room]: state events and sticky
  /// events of both types, left ones included.
  static Iterable<Event> eventsOf(Room room) sync* {
    for (final type in types) {
      for (final event
          in room.states[type]?.values ?? const <StrippedStateEvent>[]) {
        if (event is Event) yield event;
      }
      yield* room.stickyEventsOfType(type);
    }
  }
}

// ROOSTER: A [CallMembership] from a membership of the newer format (T5.2).
extension RtcCallMembership on CallMembership {
  static CallMembership? fromRtcMember(Event event, VoIP voip) {
    final content = event.content;
    final application = RtcMemberships.applicationOf(content);
    final deviceId = RtcMemberships.deviceIdOf(content);
    if (application == null || deviceId == null) return null;
    final transport = RtcMemberships.transportsOf(content).firstOrNull;
    try {
      return CallMembership(
        userId: event.senderId,
        roomId: event.roomId ?? event.room.id,
        callId: RtcMemberships.callIdOf(content),
        application: application,
        scope: 'm.room',
        backend: CallBackend.fromJson({
          'type': 'livekit',
          'livekit_alias': event.room.id,
          ...?transport,
        }),
        deviceId: deviceId,
        eventId: event.eventId,
        expiresTs: RtcMemberships.expiresAt(event).millisecondsSinceEpoch,
        membershipId: RtcMemberships.memberIdOf(content) ?? event.eventId,
        voip: voip,
      );
    } catch (e, s) {
      Logs().w('[VOIP] Ignoring an unreadable rtc membership', e, s);
      return null;
    }
  }
}
