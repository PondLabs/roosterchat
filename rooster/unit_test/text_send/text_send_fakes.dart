import 'dart:async';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/client/room.dart';

import '../pending_media/chat_harness.dart';

/// The room the SDK's fake homeserver answers every send to.
const fakeRoomId = '!1234:fakeServer.notExisting';

/// [client] joined to [fakeRoomId], encrypted (megolm) when [encrypted]:
/// the room's state says so, whether or not vodozemac is loaded.
Future<MatrixRoom> joinedRoom(MatrixClient client,
    {required bool encrypted}) async {
  final mx = client.getMatrixClient();
  await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
        nextBatch: encrypted ? 'encrypted' : 'plain',
        rooms: matrix.RoomsUpdate(join: {
          fakeRoomId: matrix.JoinedRoomUpdate(state: [
            matrix.MatrixEvent(
              type: matrix.EventTypes.RoomMember,
              stateKey: mx.userID,
              senderId: mx.userID!,
              eventId: '\$join',
              originServerTs: DateTime.now(),
              content: {'membership': 'join'},
            ),
            if (encrypted)
              matrix.MatrixEvent(
                type: matrix.EventTypes.Encryption,
                stateKey: '',
                senderId: mx.userID!,
                eventId: '\$encryption',
                originServerTs: DateTime.now(),
                content: {'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2},
              ),
          ]),
        }),
      )));
  // The Rooster client adds the room on the SDK's onSync event.
  await Future<void>.delayed(Duration.zero);
  return client.getRoom(fakeRoomId)! as MatrixRoom;
}

/// Replaces [MatrixRoom.prepareOutboundSession] for one test: each
/// preparation is counted in [rooms] (by room id) and lasts until [finish].
class PreparationSpy {
  PreparationSpy() {
    _app = MatrixRoom.prepareOutboundSession;
    MatrixRoom.prepareOutboundSession = (room) {
      rooms.add(room.id);
      return (_running = Completer<void>()).future;
    };
  }

  late final Future<void> Function(matrix.Room) _app;
  final List<String> rooms = [];
  Completer<void>? _running;

  int get count => rooms.length;

  /// The preparation in flight ends, with [error] when given.
  void finish([Object? error]) {
    final running = _running!;
    _running = null;
    error == null ? running.complete() : running.completeError(error);
  }

  void restore() => MatrixRoom.prepareOutboundSession = _app;
}

/// Typing notices turned off: Rooster's component sends nothing then
/// (`MatrixTypingIndicatorsComponent.setTypingStatus`). [calls] counts what
/// the chat asked of it.
class TypingOff implements TypingIndicatorComponent {
  int calls = 0;

  @override
  Future<void> setTypingStatus(bool status) async => calls++;
  @override
  Stream<void> get onTypingUsersUpdated => const Stream.empty();
  @override
  List<Member> get typingUsers => const [];
  @override
  bool? get typingIndicatorEnabledForRoom => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The chat harness's room whose send preparation is [target]'s: the
/// widget's triggers run into a real [MatrixRoom].
class PreparingRoom extends FakeRoom implements RoomSendPreparation {
  PreparingRoom(super.client, super.identifier,
      {required super.preparer, required this.target, this.typing});

  final MatrixRoom target;
  final TypingIndicatorComponent? typing;

  @override
  void prepareToSend() => target.prepareToSend();

  @override
  T? getComponent<T extends RoomComponent>() =>
      T == TypingIndicatorComponent && typing != null
          ? typing as T
          : super.getComponent<T>();
}
