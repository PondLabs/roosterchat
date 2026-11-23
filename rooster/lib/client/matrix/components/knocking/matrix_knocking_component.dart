import 'package:matrix/matrix.dart' as matrix;

/// Someone asking to join a room (`m.room.member` with `membership: knock`).
class KnockRequest {
  const KnockRequest({
    required this.userId,
    this.displayName,
    this.reason,
    this.requestedAt,
  });

  final String userId;
  final String? displayName;
  final String? reason;
  final DateTime? requestedAt;
}

/// Knocking (`knock` and `knock_restricted` join rules): asking to join a
/// room, and the moderators' queue of those requests.
class MatrixKnockingComponent {
  MatrixKnockingComponent(this.room);

  final matrix.Room room;

  matrix.Client get client => room.client;

  static bool isKnockJoinRule(matrix.JoinRules? rule) =>
      rule == matrix.JoinRules.knock ||
      rule == matrix.JoinRules.knockRestricted;

  bool get roomAcceptsKnocks => isKnockJoinRule(room.joinRules);

  /// Whether our request to join is waiting for a moderator.
  bool get hasPendingKnock => room.membership == matrix.Membership.knock;

  /// Whether we can ask to join: the room takes knocks and we are neither in
  /// it, invited, banned nor already waiting.
  bool get canKnock =>
      roomAcceptsKnocks && room.membership == matrix.Membership.leave;

  /// Sends a knock for a room by ID or alias without needing a joined
  /// [matrix.Room] instance.
  static Future<String> knockById(
    matrix.Client client,
    String roomIdOrAlias, {
    String? reason,
    List<String>? via,
  }) {
    final trimmed = reason?.trim();
    final servers = via?.where((s) => s.isNotEmpty).toList();
    return client.knockRoom(
      roomIdOrAlias,
      reason: trimmed == null || trimmed.isEmpty ? null : trimmed,
      via: servers == null || servers.isEmpty ? null : servers,
    );
  }

  /// Asks to join the room. [reason] is shown to the moderators.
  Future<void> knock({String? reason, List<String>? via}) async {
    await knockById(client, room.id, reason: reason, via: via);
  }

  /// Moderators answer knocks by inviting (approve) or kicking (deny), so it
  /// takes the power to do both.
  bool get canModerate => room.canInvite && room.canKick;

  static KnockRequest? _knockFromContent(
    String userId,
    Map<String, Object?> content,
    DateTime? requestedAt,
  ) {
    if (content['membership'] != matrix.Membership.knock.name) return null;
    final displayName = content['displayname'];
    final reason = content['reason'];
    return KnockRequest(
      userId: userId,
      displayName:
          displayName is String && displayName.isNotEmpty ? displayName : null,
      reason: reason is String && reason.isNotEmpty ? reason : null,
      requestedAt: requestedAt,
    );
  }

  static List<KnockRequest> _sortedRequests(Iterable<KnockRequest> requests) {
    final list = requests.toList();
    list.sort((a, b) =>
        (a.requestedAt ?? DateTime(0)).compareTo(b.requestedAt ?? DateTime(0)));
    return list;
  }

  List<KnockRequest> get pendingKnocks {
    final members = room.states[matrix.EventTypes.RoomMember];
    if (members == null) return [];
    final requests = <KnockRequest>[];
    for (final entry in members.entries) {
      final event = entry.value;
      final request = _knockFromContent(
        entry.key,
        event.content,
        event is matrix.Event ? event.originServerTs : null,
      );
      if (request != null) requests.add(request);
    }
    return _sortedRequests(requests);
  }

  /// Loads pending knocks from the homeserver (`GET /members?membership=knock`)
  /// so knocks outside a lazy-loaded `/sync` window are still returned.
  Future<List<KnockRequest>> loadPendingKnocks() async {
    final events = await client.getMembersByRoom(
      room.id,
      membership: matrix.Membership.knock,
    );
    if (events == null) return pendingKnocks;
    final byUser = <String, KnockRequest>{};
    for (final event in events) {
      final userId = event.stateKey;
      if (userId == null || userId.isEmpty) continue;
      final request = _knockFromContent(
        userId,
        event.content,
        event.originServerTs,
      );
      if (request == null) continue;
      final existing = room.states[matrix.EventTypes.RoomMember]?[userId];
      if (existing is matrix.Event &&
          existing.originServerTs.isAfter(event.originServerTs)) {
        final newer = _knockFromContent(
          userId,
          existing.content,
          existing.originServerTs,
        );
        if (newer != null) byUser[userId] = newer;
        continue;
      }
      room.setState(matrix.Event.fromMatrixEvent(event, room));
      byUser[userId] = request;
    }
    return _sortedRequests(byUser.values);
  }

  Future<void> approve(String userId) async {
    if (!canModerate) throw StateError('No power to answer knocks');
    await client.inviteUser(room.id, userId);
  }

  /// Turns the request down; [reason] goes to the person who asked.
  Future<void> deny(String userId, {String? reason}) async {
    if (!canModerate) throw StateError('No power to answer knocks');
    final trimmed = reason?.trim();
    await client.kick(
      room.id,
      userId,
      reason: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
  }
}
