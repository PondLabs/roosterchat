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

  /// Asks to join the room. [reason] is shown to the moderators.
  Future<void> knock({String? reason, List<String>? via}) async {
    final trimmed = reason?.trim();
    await client.knockRoom(
      room.id,
      reason: trimmed == null || trimmed.isEmpty ? null : trimmed,
      via: via,
    );
  }

  /// Moderators answer knocks by inviting (approve) or kicking (deny), so it
  /// takes the power to do both.
  bool get canModerate => room.canInvite && room.canKick;

  List<KnockRequest> get pendingKnocks {
    final members = room.states[matrix.EventTypes.RoomMember];
    if (members == null) return [];
    final requests = <KnockRequest>[];
    for (final entry in members.entries) {
      final event = entry.value;
      if (event.content['membership'] != matrix.Membership.knock.name) {
        continue;
      }
      final displayName = event.content['displayname'];
      final reason = event.content['reason'];
      requests.add(KnockRequest(
        userId: entry.key,
        displayName: displayName is String && displayName.isNotEmpty
            ? displayName
            : null,
        reason: reason is String && reason.isNotEmpty ? reason : null,
        requestedAt: event is matrix.Event ? event.originServerTs : null,
      ));
    }
    requests.sort((a, b) =>
        (a.requestedAt ?? DateTime(0)).compareTo(b.requestedAt ?? DateTime(0)));
    return requests;
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
