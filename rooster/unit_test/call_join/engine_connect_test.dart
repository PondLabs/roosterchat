// The copied LiveKit's Engine.connect tells the join each step of its
// connect (ConnectStep, the `// ROOSTER` hook), and the join's speed log
// times them. Here over a real WebSocket on 127.0.0.1, which this test
// serves itself: the WebSocket opening and the server's join answer are
// reported when they happen, and in order. The media is not: no SFU here,
// so the peer connections are fakes, and the test says when the primary
// one connects.
//
// Native only: it serves the WebSocket with dart:io.
@TestOn('vm')
library;

// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:livekit_client/src/core/engine.dart';
import 'package:livekit_client/src/proto/livekit_models.pb.dart' as lk_models;
import 'package:livekit_client/src/proto/livekit_rtc.pb.dart' as lk_rtc;
import 'package:rooster/client/matrix/components/voip_room/livekit_join_room.dart';

/// A peer connection that only keeps the handlers LiveKit sets on it.
class _PeerConnection implements rtc.RTCPeerConnection {
  final Map<Symbol, Object?> handlers = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) {
      handlers[invocation.memberName] = invocation.positionalArguments.first;
      return null;
    }
    throw UnimplementedError('${invocation.memberName}');
  }
}

/// The signal server: a WebSocket on 127.0.0.1 that answers the join when
/// the test says so. Writes what happens, beside the steps, to [log].
class _SignalServer {
  _SignalServer(this.log);

  final List<String> log;
  late final HttpServer _http;
  WebSocket? _socket;
  final Completer<void> _connected = Completer();
  final List<_PeerConnection> peerConnections = [];

  String get url => 'ws://127.0.0.1:${_http.port}';

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
        return;
      }
      log.add('ws_accepted ${request.uri.path}');
      _socket = await WebSocketTransformer.upgrade(request);
      _socket!.listen((_) {});
      _connected.complete();
    });
  }

  Future<void> get connected => _connected.future;

  /// The server's answer to the join, as LiveKit's SFU sends it first.
  void answerJoin() {
    log.add('join_answer_sent');
    _socket!.add(lk_rtc.SignalResponse(
            join: lk_rtc.JoinResponse(
                subscriberPrimary: true,
                room: lk_models.Room(sid: 'RM_test', name: 'room'),
                participant:
                    lk_models.ParticipantInfo(sid: 'PA_test', identity: 'me')))
        .writeToBuffer());
  }

  Future<rtc.RTCPeerConnection> createPeerConnection(
      Map<String, dynamic> configuration,
      [Map<String, dynamic> constraints = const {}]) async {
    log.add('peer_connection_created');
    final connection = _PeerConnection();
    peerConnections.add(connection);
    return connection;
  }

  /// What no SFU here can do: the primary peer connection (the subscriber,
  /// the second one made) reports it is connected.
  void mediaConnected() {
    log.add('media_connected');
    (peerConnections[1].handlers[const Symbol('onConnectionState=')]
            as Function)(
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected);
  }

  Future<void> close() async {
    await _socket?.close();
    await _http.close(force: true);
  }
}

/// Until [condition] holds, on the real clock: the WebSocket is real.
Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('waited 10 s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late List<String> log;
  late _SignalServer server;
  late Engine engine;

  setUp(() async {
    log = [];
    server = _SignalServer(log);
    await server.start();
    addTearDown(server.close);
    // The real signal client and WebSocket; only the media is faked.
    engine = Engine(
        connectOptions: const lk.ConnectOptions(autoSubscribe: false),
        roomOptions: const lk.RoomOptions(),
        peerConnectionCreate: server.createPeerConnection);
  });

  test(
      'started, then the WebSocket open, then the join answered, each when '
      'it happens', () async {
    engine.onConnectStep = (step) => log.add('STEP ${step.name}');
    final connecting = engine.connect(server.url, 'token');
    connecting.ignore();

    await server.connected;
    await until(() => log.contains('STEP signalConnected'));
    expect(log, isNot(contains('STEP joinResponse')),
        reason: 'the server has not answered the join yet');

    server.answerJoin();
    await until(() => log.contains('STEP joinResponse'));
    expect(log, isNot(contains('STEP primaryConnected')),
        reason: 'no media connected yet');

    server.mediaConnected();
    await connecting;
    // ignore: avoid_print
    print('sequence: ${log.join(' > ')}');
    expect(log.where((e) => e.startsWith('STEP')), [
      'STEP started',
      'STEP signalConnected',
      'STEP joinResponse',
      'STEP primaryConnected',
    ]);
    final accepted = log.indexWhere((e) => e.startsWith('ws_accepted'));
    expect(log.indexOf('STEP started'), lessThan(accepted));
    expect(accepted, lessThan(log.indexOf('STEP signalConnected')));
    expect(log.indexOf('STEP signalConnected'),
        lessThan(log.indexOf('join_answer_sent')));
    expect(log.indexOf('join_answer_sent'),
        lessThan(log.indexOf('STEP joinResponse')));
    expect(log.indexOf('STEP joinResponse'),
        lessThan(log.indexOf('media_connected')));
  });

  test(
      "the join's room tells its onStep during the connect, and takes the "
      'hook off after', () async {
    final steps = <lk.ConnectStep>[];
    final room = LkJoinRoom(lk.Room(engine: engine));
    final connecting = room.connect(server.url, 'token', onStep: steps.add);
    connecting.ignore();

    await server.connected;
    await until(() => steps.contains(lk.ConnectStep.signalConnected));
    server.answerJoin();
    await until(() => steps.contains(lk.ConnectStep.joinResponse));
    server.mediaConnected();
    await connecting;

    expect(steps, lk.ConnectStep.values);
    expect(engine.onConnectStep, isNull,
        reason: 'a reconnect after the join is not reported');
  });
}
