import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:rooster/client/matrix/components/typing_indicators/matrix_typing_indicators_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';

import '../pending_media/chat_harness.dart';
import '../speed_log/fake_account.dart';

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
          fakeRoomId: matrix.JoinedRoomUpdate(
              // As a homeserver's sync says it: who is in the room is
              // counted, the list itself is asked for (`GET /members`).
              summary: matrix.RoomSummary.fromJson(
                  {'m.joined_member_count': 1, 'm.invited_member_count': 0}),
              state: [
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
                    content: {
                      'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2
                    },
                  ),
              ]),
        }),
      )));
  // The Rooster client adds the room on the SDK's onSync event.
  await Future<void>.delayed(Duration.zero);
  return client.getRoom(fakeRoomId)! as MatrixRoom;
}

/// Turns [client]'s typing notices [on] or off, for every room, as the
/// account data a sync brings says it (the setting in the app's settings).
Future<void> setTypingNotices(MatrixClient client, bool on) async {
  final mx = client.getMatrixClient();
  await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
        nextBatch: on ? 'typing_on' : 'typing_off',
        accountData: [
          matrix.BasicEvent(
              type: MatrixTypingIndicatorsComponent.publicTypingIndicatorKey,
              content: {'enabled': on}),
        ],
      )));
}

/// Replaces [MatrixRoom.prepareOutboundSession] for one test: each
/// preparation is counted in [rooms] (by room id), with the account it
/// ran for in [accounts] (by client name), and lasts until [finish].
class PreparationSpy {
  PreparationSpy() {
    _app = MatrixRoom.prepareOutboundSession;
    MatrixRoom.prepareOutboundSession = (room) {
      rooms.add(room.id);
      accounts.add(room.client.clientName);
      return (_running = Completer<void>()).future;
    };
  }

  late final Future<void> Function(matrix.Room) _app;
  final List<String> rooms = [];
  final List<String> accounts = [];
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

/// The fake homeserver with each `PUT /send` refused (403) while [refuse],
/// and held until [hold] completes while it is set.
class SendTransport extends FakeTransport {
  bool refuse = false;
  Completer<void>? hold;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'PUT' && request.url.path.contains('/send/')) {
      if (refuse) {
        return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(
                {'errcode': 'M_FORBIDDEN', 'error': 'Not allowed'}))),
            403,
            headers: {'content-type': 'application/json'},
            request: request);
      }
      await hold?.future;
    }
    return super.send(request);
  }
}

/// Waits, on real time, until [done] holds (5 s at most).
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (!done()) throw StateError('timed out');
}

/// Own text messages in [room]'s timeline: [failed] refused by the server,
/// then [pending] whose `PUT /send` is held by [transport] (so it stays
/// sending), each sent [gap] after the one before; with [queued], one more
/// pending behind it in the room's queue.
Future<Timeline> timelineWithSends(MatrixRoom room, SendTransport transport,
    {required String failed,
    required String pending,
    String? queued,
    Duration gap = Duration.zero}) async {
  final timeline = await room.getTimeline();
  TimelineEvent? own(String body) => timeline.events
      .where((e) => e is TimelineEventMessage && e.body == body)
      .firstOrNull;

  transport.refuse = true;
  // The SDK marks the message failed, then throws the server's error.
  await room.sendMessage(message: failed).then((_) {}, onError: (_) {});
  await until(() => own(failed)?.status == TimelineEventStatus.error);
  transport
    ..refuse = false
    ..hold = Completer<void>();
  await Future<void>.delayed(gap);
  unawaited(room.sendMessage(message: pending));
  await until(() => own(pending)?.status == TimelineEventStatus.sending);
  if (queued != null) {
    await Future<void>.delayed(gap);
    unawaited(room.sendMessage(message: queued));
    await until(() => own(queued)?.status == TimelineEventStatus.sending);
  }
  return timeline;
}
