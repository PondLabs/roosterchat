// What ties the warm-up to the app: the hook the page and Who's around call
// (VoipRoomView.warmUpCall, CallWarmUp.warm) reaches the Matrix component's
// backend, and not while a join runs or a call is on; a /healthz that fails
// is never an error; a call token that arrives after the logout is dropped.
//
// Pure Dart (no dart:io): the token service is a MockClient.
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/call_token_service.dart';
import 'package:rooster/client/matrix/components/voip_room/call_warm_up.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:test/test.dart';

import 'fakes.dart';

class _Client implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements MatrixRoom {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A backend that counts its warm-ups, and whose joins end when the test
/// says so.
class _Backend implements MatrixLivekitBackend {
  int warmUps = 0;
  final joins = <Completer<VoipSession?>>[];

  @override
  Future<void> warmUp() async => warmUps++;

  @override
  Future<VoipSession?> join(
      {Future<void> Function()? leavePrevious, Future<void>? hangUp}) {
    final join = Completer<VoipSession?>();
    joins.add(join);
    return join.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements VoipSession {
  @override
  VoipState get state => VoipState.connected;

  @override
  Stream<void> get onStateChanged => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _grantBody() => '{"url": "wss://sfu.example.org", "jwt": '
    '"${jwtUntil(DateTime.now().add(const Duration(hours: 1)))}"}';

void main() {
  test(
      "the hook of the page and of Who's around reaches the backend, and not "
      'while joining or in the call', () async {
    final voip = MatrixVoipRoomComponent(_Client(), _Room());
    final backend = _Backend();
    voip.backend = backend;

    VoipRoomView.warmUpCall(voip);
    await settle();
    expect(backend.warmUps, 1, reason: "the page's hook, as the app has it");
    CallWarmUp.warm(voip);
    await settle();
    expect(backend.warmUps, 2, reason: "Who's around calls this");

    final joining = voip.joinCall();
    CallWarmUp.warm(voip);
    await settle();
    expect(backend.warmUps, 2, reason: 'not while a join runs');

    backend.joins.single.complete(_Session());
    await joining;
    CallWarmUp.warm(voip);
    await settle();
    expect(backend.warmUps, 2, reason: 'not while in the call');
  });

  test(
      'a /healthz that fails before the tokens arrive is not an unhandled '
      'error', () async {
    final gate = Gate();
    final tokens = CallTokenService(client: MockClient((request) async {
      if (request.url.path.endsWith('/healthz')) {
        throw http.ClientException('refused', request.url);
      }
      await gate.passed;
      return http.Response(_grantBody(), 200);
    }));
    final warm = CallWarmUp(host: FakeHost(Journal()), tokens: tokens).run();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    gate.open();
    await warm;
    expect(tokens.holdsGrant('!room:example.org', 'DEVICE'), isTrue);
  });

  test('a call token that arrives after the logout is not kept', () async {
    final gate = Gate();
    final tokens = CallTokenService(client: MockClient((request) async {
      await gate.passed;
      return http.Response(_grantBody(), 200);
    }));
    final host = FakeHost(Journal());
    // The /sfu/get is on its way when the account logs out.
    final grant = tokens.sfuGrant(Uri.parse(host.focus),
        roomId: host.roomId, deviceId: host.deviceId, openId: host.openIdToken);
    await settle();
    tokens.close();
    gate.open();
    await grant;
    expect(tokens.holdsGrant(host.roomId, host.deviceId), isFalse);
  });
}
