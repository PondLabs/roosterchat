import 'dart:async';

import 'package:matrix/encryption/room_key_bundle.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Whether inviting someone to a room shares its encrypted history
/// (Matrix v1.19, MSC4268).
enum HistorySharingState {
  /// The room is not encrypted: there are no keys to share.
  notEncrypted,

  /// The room's history visibility keeps earlier messages from newcomers
  /// (`joined`, or none stated): nothing is shared.
  keptToMembers,

  /// We turned sharing off for this room.
  off,

  /// Inviting shares the keys of the messages newcomers may read.
  on,
}

/// Someone shared this room's history with us when they invited us.
class HistorySharingNotice {
  final String senderName;
  final int keys;
  const HistorySharingNotice({required this.senderName, required this.keys});
}

/// What the room's security settings show and change about history sharing.
abstract class HistorySharingController {
  HistorySharingState get state;
  Future<void> setShareOnInvite(bool on);

  /// The history someone shared with us here since the app started.
  HistorySharingNotice? get notice;

  /// Fires when [state] or [notice] may have changed.
  Stream<void> get changes;
}

class MatrixHistorySharing implements HistorySharingController {
  /// Our own choice for the room, in its account data (only we see it).
  static const accountDataType = 'chat.commet.history_sharing';
  static const _shareOnInviteKey = 'share_on_invite';

  final matrix.Room room;
  MatrixHistorySharing(this.room);

  RoomKeyBundleManager? get _bundles => room.client.encryption?.roomKeyBundle;

  /// On unless we turned it off: the room's history visibility already says
  /// whether newcomers may read earlier messages.
  static bool shareOnInvite(matrix.Room room) =>
      room.roomAccountData[accountDataType]?.content[_shareOnInviteKey] !=
      false;

  static HistorySharingState stateOf(matrix.Room room) {
    if (!room.encrypted) return HistorySharingState.notEncrypted;
    // As the SDK reads it when it shares: the room's state, and what the
    // syncs brought when the state missed it.
    final visibility =
        room.client.encryption?.roomKeyBundle.historyVisibilityOf(room) ??
            room.historyVisibility;
    if (!roomSharesHistoryOnInvite(visibility)) {
      return HistorySharingState.keptToMembers;
    }
    return shareOnInvite(room)
        ? HistorySharingState.on
        : HistorySharingState.off;
  }

  /// Invites [userId], sharing the room's history when [stateOf] says so.
  static Future<void> invite(
      matrix.Client client, String roomId, String userId) async {
    final room = client.getRoomById(roomId);
    if (room == null) return client.inviteUser(roomId, userId);
    // The history visibility is in memory once the room's state is.
    await room.postLoad();
    await room.invite(userId,
        shareHistory: stateOf(room) == HistorySharingState.on);
  }

  @override
  HistorySharingState get state => stateOf(room);

  @override
  Future<void> setShareOnInvite(bool on) async {
    final content = {_shareOnInviteKey: on};
    await room.client.setAccountDataPerRoom(
        room.client.userID!, room.id, accountDataType, content);
    room.roomAccountData[accountDataType] =
        matrix.BasicEvent(type: accountDataType, content: content);
  }

  @override
  HistorySharingNotice? get notice {
    final last = _bundles?.lastImport(room.id);
    if (last == null || last.imported == 0) return null;
    return HistorySharingNotice(
      senderName: room
          .unsafeGetUserFromMemoryOrFallback(last.senderId)
          .calcDisplayname(),
      keys: last.imported,
    );
  }

  @override
  Stream<void> get changes {
    final controller = StreamController<void>();
    final subscriptions = <StreamSubscription>[];
    controller.onListen = () {
      // A sync may change the history visibility or our own choice.
      subscriptions
          .add(room.client.onSync.stream.listen((_) => controller.add(null)));
      final bundles = _bundles;
      if (bundles != null) {
        subscriptions.add(bundles.onImported.stream
            .where((i) => i.roomId == room.id)
            .listen((_) => controller.add(null)));
      }
      // ignore: discarded_futures
      room.postLoad().then((_) => controller.add(null));
    };
    controller.onCancel = () async {
      for (final s in subscriptions) {
        await s.cancel();
      }
    };
    return controller.stream;
  }
}
