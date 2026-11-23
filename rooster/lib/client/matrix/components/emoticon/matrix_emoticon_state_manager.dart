import 'dart:async';
import 'dart:convert';

import 'package:rooster/client/matrix/components/emoticon/matrix_image_pack_types.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:matrix/matrix.dart' as matrix;

abstract class MatrixEmoticonStateManager {
  Map<String, dynamic> getState(String packKey);

  Map<String, dynamic> getAllStates();

  Future<void> setState(String packKey, Map<String, dynamic> content);

  Stream<void> get onStateChanged;

  String get id;
}

class MatrixEmoticonPersonalStateManager implements MatrixEmoticonStateManager {
  MatrixClient client;

  StreamController<void> onStateChangedController =
      StreamController.broadcast();

  MatrixEmoticonPersonalStateManager(this.client) {
    var mx = client.getMatrixClient();

    mx.onLoginStateChanged.stream
        .where((event) => event == matrix.LoginState.loggedIn)
        .listen((event) async {
      if (mx.accountDataLoading != null) {
        await mx.accountDataLoading;
      }

      onStateChangedController.add(null);
    });

    mx.onSync.stream.where((e) => e.accountData != null).listen((update) {
      if (update.accountData?.any((e) => _accountDataTypes.contains(e.type)) ==
          true) {
        onStateChangedController.add(null);
      }
    });
  }

  static const _accountDataTypes = {
    ImagePackTypes.user,
    ImagePackTypes.legacyUser,
    ImagePackTypes.rooms,
    ImagePackTypes.legacyRooms,
  };

  @override
  Stream<void> get onStateChanged => onStateChangedController.stream;

  @override
  Map<String, dynamic> getAllStates() {
    var state = getState(ImagePackTypes.userPackKey);
    if (state.isEmpty) return {};
    return {ImagePackTypes.userPackKey: state};
  }

  /// Written to the stable `m.image_pack`, which is read first from then on.
  @override
  Future<void> setState(String packKey, Map<String, dynamic> content) {
    return client.getMatrixClient().setAccountData(
        client.getMatrixClient().userID!, ImagePackTypes.user, content);
  }

  /// `m.image_pack` when the account has it (even emptied), the legacy
  /// `im.ponies.user_emotes` otherwise.
  @override
  Map<String, dynamic> getState(String packKey) {
    final accountData = client.getMatrixClient().accountData;
    final event = accountData[ImagePackTypes.user] ??
        accountData[ImagePackTypes.legacyUser];
    // A copy, so callers can edit it before the server accepts the change
    return _copyContent(event?.content);
  }

  @override
  String get id => client.identifier;
}

class MatrixEmoticonRoomStateManager implements MatrixEmoticonStateManager {
  matrix.Room room;

  StreamController<void> onStateChangedController =
      StreamController.broadcast();

  MatrixEmoticonRoomStateManager(this.room) {
    var mx = room.client;

    mx.onRoomState.stream
        .where((event) =>
            event.roomId == room.id &&
            (event.state.type == ImagePackTypes.room ||
                event.state.type == ImagePackTypes.legacyRoom))
        .listen((event) {
      onStateChangedController.add(null);
    });

    onStateChangedController.add(null);
  }

  /// Both state types, the stable one winning per state key
  /// ([readRoomImagePacks]).
  @override
  Map<String, dynamic> getAllStates() => readRoomImagePacks(room);

  @override
  Map<String, dynamic> getState(String packKey) {
    return _copyContent(getAllStates()[packKey]);
  }

  /// Written to the stable `m.room.image_pack`, which hides a legacy pack
  /// with the same state key from then on.
  @override
  Future<void> setState(String packKey, Map<String, dynamic> content) async {
    var event = await room.client
        .setRoomStateWithKey(room.id, ImagePackTypes.room, packKey, content);

    // Fall back to what we sent, so a following edit (e.g. the next file of a
    // batch upload) doesn't build on stale state before the sync arrives.
    var result = await room.getEventById(event) ??
        matrix.StrippedStateEvent(
            type: ImagePackTypes.room,
            content: content,
            senderId: room.client.userID!,
            stateKey: packKey);

    // The room's first pack has no state map to add to yet
    room.states.putIfAbsent(ImagePackTypes.room, () => {})[packKey] = result;
  }

  @override
  Stream<void> get onStateChanged => onStateChangedController.stream;

  @override
  String get id => room.id;
}

Map<String, dynamic> _copyContent(Map<String, dynamic>? content) =>
    content == null ? {} : jsonDecode(jsonEncode(content));
