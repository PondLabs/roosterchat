import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/history_sharing/matrix_history_sharing.dart';

/// Why the homeserver turned a moderation action down, for the screens to
/// say so in the app's language.
enum ModerationFailure {
  /// `M_FORBIDDEN`: our power level is too low, or the target's too high.
  forbidden,

  /// `M_NOT_FOUND`: the room, the member or the message is not known.
  notFound,

  /// `M_LIMIT_EXCEEDED`.
  rateLimited,

  /// Anything else, a lost connection included.
  other;

  static ModerationFailure of(Object error) {
    if (error is! matrix.MatrixException) return other;
    return switch (error.errcode) {
      'M_FORBIDDEN' => forbidden,
      'M_NOT_FOUND' => notFound,
      'M_LIMIT_EXCEEDED' => rateLimited,
      _ => other,
    };
  }
}

/// Someone banned from the room, as the room's member list has them.
class BannedMember {
  const BannedMember(
      {required this.userId, this.displayName, this.reason, this.bannedBy});

  final String userId;
  final String? displayName;

  /// The `reason` of the ban, when the moderator gave one.
  final String? reason;

  /// Who sent the ban.
  final String? bannedBy;

  static BannedMember? fromEvent(matrix.StrippedStateEvent event) {
    final userId = event.stateKey;
    if (userId == null || userId.isEmpty) return null;
    if (event.content['membership'] != 'ban') return null;
    final name = event.content['displayname'];
    final reason = event.content['reason'];
    return BannedMember(
      userId: userId,
      displayName: name is String && name.isNotEmpty ? name : null,
      reason: reason is String && reason.trim().isNotEmpty ? reason : null,
      bannedBy: event.senderId,
    );
  }
}

/// `m.room.server_acl`, which the SDK has no constant for.
const serverAclType = 'm.room.server_acl';

/// Room moderation with an optional reason: kick, ban, unban, invite and
/// delete a message, and the list of banned members.
class MatrixRoomModeration {
  MatrixRoomModeration(this.room);

  final matrix.Room room;

  matrix.Client get client => room.client;

  bool get canKick => room.canKick;

  /// Unbanning takes the `ban` level, like banning.
  bool get canBan => room.canBan;

  bool get canInvite => room.canInvite;

  bool get canRedact => room.canRedact;

  bool get canEditServerAcl => room.canChangeStateEvent(serverAclType);

  bool get canEditPolicyServer =>
      room.canChangeStateEvent(matrix.EventTypes.RoomPolicy);

  /// Whether any moderation screen has something for us.
  bool get canModerate => canBan || canEditServerAcl || canEditPolicyServer;

  /// The reason as typed, or null when only blank: an empty reason is left
  /// out of the request rather than sent as `""`.
  static String? cleanReason(String? reason) {
    final trimmed = reason?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// The banned members, sorted by user ID. Asks the server
  /// (`GET /members?membership=ban`), as lazy loading may have left some out
  /// of the local state.
  Future<List<BannedMember>> fetchBanned() async {
    final events = await client.getMembersByRoom(room.id,
            membership: matrix.Membership.ban) ??
        const <matrix.MatrixEvent>[];
    final banned = <String, BannedMember>{};
    for (final event in events) {
      final member = BannedMember.fromEvent(event);
      if (member != null) banned[member.userId] = member;
    }
    return banned.values.toList()..sort((a, b) => a.userId.compareTo(b.userId));
  }

  Future<void> unban(String userId, {String? reason}) =>
      client.unban(room.id, userId, reason: cleanReason(reason));

  Future<void> kick(String userId, {String? reason}) =>
      client.kick(room.id, userId, reason: cleanReason(reason));

  Future<void> ban(String userId, {String? reason}) =>
      client.ban(room.id, userId, reason: cleanReason(reason));

  /// Invites through the room, sharing its history when its settings say
  /// so, as `MatrixHistorySharing.invite` does.
  Future<void> invite(String userId, {String? reason}) async {
    await room.postLoad();
    await room.invite(userId,
        reason: cleanReason(reason),
        shareHistory:
            MatrixHistorySharing.stateOf(room) == HistorySharingState.on);
  }

  Future<String?> redact(String eventId, {String? reason}) =>
      room.redactEvent(eventId, reason: cleanReason(reason));
}

/// The banned list on a moderation screen: unbanning only takes someone off
/// once the server agreed, so a refusal leaves the list as it was.
class BannedMembersList {
  BannedMembersList(this.moderation);

  final MatrixRoomModeration moderation;

  List<BannedMember> members = const [];

  Future<void> refresh() async {
    members = await moderation.fetchBanned();
  }

  /// Throws what the server answered; [members] is then unchanged.
  Future<void> unban(String userId, {String? reason}) async {
    await moderation.unban(userId, reason: reason);
    members = [
      for (final member in members)
        if (member.userId != userId) member
    ];
  }
}
