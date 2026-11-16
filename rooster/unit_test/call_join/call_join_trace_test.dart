// The voice join's `voice_join` span: each step with its duration, the
// SFU's host class and region, the microphone published, and the first
// remote audio, unavailable when nobody speaks. A join without a held token
// lists its requests by route under the span.
import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/call_token_service.dart';
import 'package:rooster/client/matrix/components/voip_room/call_warm_up.dart';
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
  FakeLivekitRoom createSession(
      LivekitJoinRoom room, Future<void> microphonePublished) {
    heartbeat = Timer.periodic(const Duration(milliseconds: 20), (_) {
      client.put(Uri.parse('${_HttpHost.homeserver}/_matrix/client/v3/rooms/'
          '${Uri.encodeComponent(roomId)}/state/'
          'org.matrix.msc3401.call.member/key'));
    });
    return super.createSession(room, microphonePublished);
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
    expect(steps, contains('sfu_region_other'));
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

  test("a region's own text never reaches the report", () async {
    final host = FakeHost(journal)..room.region = 'Sfu1.Example.Org';

    final span = await joinAndWait(host);

    expect(stepsOf(span), contains('sfu_region_other'));
    final report = buildSpeedReport(log).toLowerCase();
    expect(report, isNot(contains('sfu1')));
    expect(report, isNot(contains('example')));
    expect(report, isNot(contains('invalid_name')),
        reason: 'every step of the join is on the fixed list');
  });

  test(
      'a microphone that never opens is unavailable once the window ends, '
      'and the span closes', () async {
    final host = FakeHost(journal);
    host.room.microphoneGate = Gate();

    final span = await joinAndWait(host);

    expect(span.isFinished, isTrue);
    expect(log.openSpans, isEmpty);
    expect(stepsOf(span)['microphone_published']?.available, isFalse);
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

  group('the connect in three steps', () {
    const all = [
      lk.ConnectStep.started,
      lk.ConnectStep.signalConnected,
      lk.ConnectStep.joinResponse,
      lk.ConnectStep.primaryConnected,
    ];
    const parts = [
      'connect_websocket',
      'connect_join_response',
      'connect_media',
    ];

    test(
        'each step timed inside the connect, and together no longer than '
        'it', () async {
      final host = FakeHost(journal)..room.attemptSteps = [all];

      final span = await joinAndWait(host);
      final steps = stepsOf(span);

      final connect = steps['connect']!;
      var sum = Duration.zero;
      for (final part in parts) {
        final step = steps[part];
        expect(step?.available, isTrue, reason: '$part has a duration');
        expect(step!.duration!, greaterThan(Duration.zero), reason: part);
        expect(step.start, greaterThanOrEqualTo(connect.start), reason: part);
        expect(step.start + step.duration!,
            lessThanOrEqualTo(connect.start + connect.duration!),
            reason: part);
        sum += step.duration!;
      }
      expect(sum, lessThanOrEqualTo(connect.duration!));
      expect(
          steps['connect_join_response']!.start,
          steps['connect_websocket']!.start +
              steps['connect_websocket']!.duration!);
      final report = buildSpeedReport(log);
      // ignore: avoid_print
      print(report);
      expect(report, isNot(contains('invalid_name')));
    });

    test('a room that reports nothing: the three unavailable, the join done',
        () async {
      final host = FakeHost(journal);

      final span = await joinAndWait(host);
      final steps = stepsOf(span);

      expect(span.outcome, 'ok');
      expect(steps['connect']?.available, isTrue);
      for (final part in parts) {
        expect(steps[part]?.available, isFalse, reason: part);
      }
    });

    test(
        'a connection that fails after the WebSocket: the rest unavailable, '
        'the join failed', () async {
      final host = FakeHost(journal)
        ..room.attemptSteps = [
          [lk.ConnectStep.started, lk.ConnectStep.signalConnected]
        ]
        ..room.connectError = StateError('no join answer');

      await expectLater(
          CallJoin(host: host, tokens: fakeTokenService(journal), log: log)
              .run(),
          throwsStateError);

      final span = log.spans.toList().single;
      final steps = stepsOf(span);
      expect(span.outcome, 'failed');
      expect(steps['connect_websocket']?.available, isTrue);
      expect(steps['connect_join_response']?.available, isFalse);
      expect(steps['connect_media']?.available, isFalse);
    });

    test("a region's second attempt inside one connect: only its own moments",
        () async {
      final host = FakeHost(journal)
        ..room.attemptSteps = [
          [
            lk.ConnectStep.started,
            lk.ConnectStep.signalConnected,
            lk.ConnectStep.joinResponse,
            // LiveKit tries the next region: the engine starts again.
            lk.ConnectStep.started,
            lk.ConnectStep.signalConnected,
          ]
        ];

      final span = await joinAndWait(host);
      final steps = stepsOf(span);

      final connect = steps['connect']!;
      expect(steps['connect_websocket']?.available, isTrue);
      expect(steps['connect_websocket']!.start - connect.start,
          greaterThanOrEqualTo(host.room.stepGap * 4),
          reason: 'from the second start');
      expect(steps['connect_join_response']?.available, isFalse,
          reason: "the first attempt's answer is not the second's");
      expect(steps['connect_media']?.available, isFalse);
    });

    test(
        'a held token the SFU refuses: the steps are those of the connect '
        'that completed, none of the refused one', () async {
      final jwts = <String>[];
      final tokens = CallTokenService(client: MockClient((request) async {
        if (request.url.path != '/sfu/get') return http.Response('', 200);
        jwts.add(jwtUntil(DateTime.now().add(const Duration(minutes: 10)),
            id: 'g${jwts.length + 1}'));
        return http.Response(
            jsonEncode({'url': 'wss://sfu.example.org', 'jwt': jwts.last}),
            200);
      }));
      final host = FakeHost(journal);
      // The call token, held since the page opened.
      await CallWarmUp(host: host, tokens: tokens).run();
      host.room
        ..refusedTokens.add(jwts.single)
        ..attemptSteps = [
          all.sublist(0, 3),
          [lk.ConnectStep.started, lk.ConnectStep.signalConnected],
        ];

      final span = await joinAndWait(host, tokens: tokens);
      final steps = stepsOf(span);

      expect(host.room.connectTokens, jwts, reason: 'refused, then a new one');
      expect(jwts, hasLength(2));
      expect(span.outcome, 'ok');
      expect(steps['connect_websocket']?.available, isTrue);
      expect(steps['connect_join_response']?.available, isFalse,
          reason: "the refused connect's answer is not the second's");
      expect(steps['connect_media']?.available, isFalse);
    });
  });
}
