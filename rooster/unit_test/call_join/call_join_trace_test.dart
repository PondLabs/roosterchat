// The voice join's `voice_join` span: each step with its duration, the
// SFU's host class and region, the microphone published, and the first
// remote audio, unavailable when nobody speaks. A join without a held token
// lists its requests by route under the span.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/call_token_service.dart';
import 'package:rooster/client/matrix/components/voip_room/livekit_join_room.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// A host whose OpenID request and membership write are real HTTP requests
/// (to an in-memory homeserver), so the speed log sees them.
class _HttpHost extends FakeHost {
  _HttpHost(super.journal, this.client);

  final http.Client client;

  static const homeserver = 'https://matrix.example.org';

  @override
  Future<matrix.OpenIdCredentials> openIdToken() async {
    journal.add('openid');
    await client.post(Uri.parse('$homeserver/_matrix/client/v3/user/'
        '${Uri.encodeComponent('@me:example.org')}/openid/request_token'));
    return FakeHost.credentials;
  }

  @override
  Future<void> writeMembership(List<Uri> foci) async {
    journal.add('membership_write');
    await client.put(Uri.parse('$homeserver/_matrix/client/v3/rooms/'
        '${Uri.encodeComponent(roomId)}/state/org.matrix.msc3401.call.member/'
        '${Uri.encodeComponent(membershipKey)}'));
  }
}

/// A host whose session sends a request from a timer, as the real session's
/// membership heartbeat does, for as long as the call lasts.
class _HeartbeatHost extends FakeHost {
  _HeartbeatHost(super.journal, this.client);

  final http.Client client;
  Timer? heartbeat;

  @override
  FakeLivekitRoom createSession(LivekitJoinRoom room) {
    heartbeat = Timer.periodic(const Duration(milliseconds: 20), (_) {
      client.put(Uri.parse('${_HttpHost.homeserver}/_matrix/client/v3/rooms/'
          '${Uri.encodeComponent(roomId)}/state/'
          'org.matrix.msc3401.call.member/key'));
    });
    return super.createSession(room);
  }
}

void main() {
  late SpeedLog log;
  late Journal journal;

  setUp(() {
    log = SpeedLog();
    journal = Journal();
  });

  http.Client recorded(http.Client inner) => SpeedHttpClient(
      inner: inner,
      log: log,
      hosts: HostClassifier(homeserver: () => Uri.parse(_HttpHost.homeserver)));

  Future<SpeedSpan> joinAndWait(FakeHost host,
      {CallTokenService? tokens,
      Duration window = const Duration(milliseconds: 50)}) async {
    await CallJoin(
            host: host,
            tokens: tokens ?? fakeTokenService(journal),
            log: log,
            remoteAudioWindow: window)
        .run();
    // The microphone publishes and the window for remote audio runs out.
    await Future<void>.delayed(window * 2);
    return log.spans.toList().single;
  }

  Map<String, SpanStep> stepsOf(SpeedSpan span) =>
      {for (final step in span.steps) step.name: step};

  test(
      'a join without a held token: each step timed, host class, region, '
      'microphone, and no remote audio when nobody speaks', () async {
    final homeserver = MockClient((_) async => http.Response('{}', 200));
    final host = _HttpHost(journal, recorded(homeserver))..room.region = 'gru1';
    final tokens =
        CallTokenService(client: recorded(MockClient((request) async {
      journal.add('sfu_get');
      return http.Response(
          '{"url": "wss://sfu.example.org", "jwt": "secret-jwt"}', 200);
    })));

    final span = await joinAndWait(host, tokens: tokens);
    final steps = stepsOf(span);

    expect(span.name, 'voice_join');
    expect(span.outcome, 'ok');
    for (final step in [
      'leave_previous',
      'output_device',
      'foci',
      'openid_token',
      'sfu_token',
      'membership_clear_wait',
      'membership_write',
      'connect',
      'microphone_options',
      'microphone_open',
      'microphone_published',
    ]) {
      expect(steps[step]?.available, isTrue, reason: '$step has a duration');
    }
    expect(steps, contains('sfu_self_hosted'));
    expect(steps, contains('sfu_region_gru1'));
    expect(steps['first_remote_audio']?.available, isFalse,
        reason: 'nobody spoke');

    // The requests of the join, by route, linked to the span.
    final requests = log.requests
        .toList()
        .where((r) => r.operationId == span.id)
        .groupListsBy((r) => '${r.method} ${r.route} ${r.hostClass.label}');
    final counts = {
      for (final entry in requests.entries) entry.key: entry.value.length
    };
    expect(counts, {
      'POST /_matrix/client/v3/user/{userId}/openid/request_token homeserver':
          1,
      'POST /sfu/get token_service': 1,
      'PUT /_matrix/client/v3/rooms/{roomId}/state/{eventType}/{stateKey} '
          'homeserver': 1,
    });

    final report = buildSpeedReport(log);
    // ignore: avoid_print
    print('requests of the join by route: $counts\n\n$report');
    expect(report, contains('first_remote_audio unavailable'));
    for (final secret in [
      'example.org',
      'secret-jwt',
      'openid-token',
      '@me',
      '!room',
      'DEVICE',
    ]) {
      expect(report, isNot(contains(secret)), reason: 'no content: $secret');
    }
  });

  test('someone speaking times the first remote audio', () async {
    final host = FakeHost(journal);
    unawaited(host.room.roomEvents.done);
    Timer(const Duration(milliseconds: 10),
        () => host.room.roomEvents.add(JoinRoomEvent.remoteSpeaking));

    final span =
        await joinAndWait(host, window: const Duration(milliseconds: 200));

    expect(stepsOf(span)['first_remote_audio']?.available, isTrue);
  });

  test('a LiveKit Cloud SFU that reports no region', () async {
    final host = FakeHost(journal);
    host.room.prepare.open();

    final span = await joinAndWait(host,
        tokens:
            fakeTokenService(journal, sfu: 'wss://project-abc.livekit.cloud'));
    final steps = stepsOf(span);

    expect(steps, contains('sfu_livekit_cloud'));
    expect(steps['prepare_connection']?.available, isTrue);
    expect(steps['sfu_region']?.available, isFalse);
  });

  test('a join that fails ends its span as failed', () async {
    final host = FakeHost(journal);
    host.room.connectError = StateError('no SFU');

    await expectLater(
        CallJoin(host: host, tokens: fakeTokenService(journal), log: log).run(),
        throwsStateError);

    expect(log.spans.toList().single.outcome, 'failed');
  });

  test(
      "the session's requests and the previous call's hang up are not the "
      "join's", () async {
    final client = recorded(MockClient((_) async => http.Response('{}', 200)));
    final host = _HeartbeatHost(journal, client);
    addTearDown(() => host.heartbeat?.cancel());

    await CallJoin(
            host: host,
            tokens: fakeTokenService(journal),
            log: log,
            remoteAudioWindow: const Duration(milliseconds: 10))
        .run(
            leavePrevious: () => client.put(
                Uri.parse('${_HttpHost.homeserver}/_matrix/client/v3/rooms/'
                    '${Uri.encodeComponent('!other:example.org')}/state/'
                    'org.matrix.msc3401.call.member/key')));
    // Some heartbeats of the call, after the span ended.
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final span = log.spans.toList().single;
    final requests = log.requests.toList();
    expect(requests.length, greaterThanOrEqualTo(3),
        reason: 'the hang up and a few heartbeats');
    expect(requests.where((r) => r.operationId == span.id), isEmpty);
    expect(requests.every((r) => r.operationId == null), isTrue);
  });
}
