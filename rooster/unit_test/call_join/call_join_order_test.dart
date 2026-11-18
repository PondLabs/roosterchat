// The voice join waited for each step in turn: the previous call's whole
// hang up, then the speakers, the tokens, LiveKit's warm-up, the membership,
// the connection, and only then the microphone. What nobody else sees now
// runs beside the rest; what the people in the call see keeps its order.
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/voip_room/call_join.dart';
import 'package:rooster/client/matrix/components/voip_room/call_membership_writes.dart';
import 'package:rooster/client/matrix/components/voip_room/call_token_service.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  late Journal journal;
  late FakeHost host;

  setUp(() {
    journal = Journal();
    host = FakeHost(journal);
    // The sequence of each scenario, for the record.
    // ignore: avoid_print
    addTearDown(() => print('sequence: ${journal.entries.join(' > ')}'));
  });

  CallJoin<FakeLivekitRoom> join({CallTokenService? tokens}) => CallJoin(
      host: host,
      tokens: tokens ?? fakeTokenService(journal),
      log: SpeedLog(),
      remoteAudioWindow: const Duration(milliseconds: 1));

  /// The steps the people in the call can see.
  const visible = {
    'previous_clear',
    'membership_write',
    'connect',
    'microphone_published',
  };

  test(
      'others see the previous clear, our membership and the connection '
      'side by side, then the microphone', () async {
    final hangUp = Gate();
    final joining = join().run(leavePrevious: () async {
      await hangUp.passed;
      journal.add('previous_clear');
    });
    await settle();
    hangUp.open();
    await joining;
    await settle();

    final seen = journal.only(visible);
    expect(seen.first, 'previous_clear');
    expect(
        seen.sublist(1, 3), unorderedEquals(['membership_write', 'connect']));
    expect(seen.last, 'microphone_published');
    expect(
        journal.before('membership_written', 'microphone_published'), isTrue);
  });

  group('switching channels', () {
    test('the tokens are asked for while the previous call hangs up', () async {
      final hangUp = Gate();
      final joining = join().run(leavePrevious: () async {
        await hangUp.passed;
        journal.add('previous_clear');
      });
      await settle();

      expect(journal.entries, containsAll(['openid', 'sfu_get']));
      expect(journal.entries, isNot(contains('previous_clear')));
      expect(journal.entries, isNot(contains('membership_write')),
          reason: 'our membership waits for the previous clear');
      expect(journal.entries, isNot(contains('connect')));

      hangUp.open();
      await joining;
      expect(journal.before('previous_clear', 'membership_write'), isTrue);
    });

    test('our membership waits for a clear still in flight after the hang up',
        () async {
      final clear = Completer<void>();
      final joining = join().run(leavePrevious: () async {
        // The hang up gave up waiting (it is bounded); its clear goes on.
        CallMembershipWrites.clearing(host.membershipKey,
            clear.future.then((_) => journal.add('previous_clear')));
      });
      await settle();
      expect(journal.entries, isNot(contains('membership_write')));

      clear.complete();
      await joining;
      expect(journal.before('previous_clear', 'membership_write'), isTrue);
    });
  });

  group('prepareConnection', () {
    test('a self-hosted SFU on native: not called, the join completes',
        () async {
      await join().run();

      expect(journal.entries, isNot(contains('prepare')));
      expect(journal.entries, contains('connected'));
    });

    test(
        'a self-hosted SFU on the web: started, not waited for '
        '(it never ends here)', () async {
      host.web = true;

      await join().run();

      expect(journal.before('prepare', 'connect'), isTrue);
      expect(journal.entries, isNot(contains('prepared')));
      expect(journal.entries, contains('connected'));
    });

    test('a LiveKit Cloud SFU: it ends before the connection, as before',
        () async {
      final joining = join(
              tokens: fakeTokenService(journal,
                  sfu: 'wss://project-abc.livekit.cloud'))
          .run();
      await settle();
      expect(journal.entries, contains('prepare'));
      expect(journal.entries, isNot(contains('connect')),
          reason: 'the region it picks is only used if it finished first');

      host.room.prepare.open();
      await joining;
      expect(journal.before('prepared', 'connect'), isTrue);
    });
  });

  test(
      'the speakers are picked while the token is asked for, and before the '
      'connection', () async {
    host.outputGate = Gate();
    final token = Gate();
    final joining =
        join(tokens: CallTokenService(client: MockClient((request) async {
      journal.add('sfu_get');
      await token.passed;
      journal.add('sfu_answered');
      return http.Response('{"url": "wss://sfu.example.org", "jwt": "j"}', 200);
    }))).run();
    await settle();
    expect(journal.entries, containsAll(['output_device', 'sfu_get']));
    expect(journal.entries, isNot(contains('sfu_answered')));

    token.open();
    await settle();
    expect(journal.entries, contains('sfu_answered'));
    expect(journal.entries, isNot(contains('connect')),
        reason: 'the speakers are not picked yet');

    host.outputGate.open();
    await joining;
    expect(journal.before('output_device_done', 'connect'), isTrue);
  });

  test("the microphone's options and capture are ready during the connection",
      () async {
    host.room.connectGate = Gate();
    final joining = join().run();
    await settle();

    expect(journal.entries, contains('connect'));
    expect(journal.entries, isNot(contains('connected')));
    expect(journal.entries,
        containsAll(['microphone_options', 'microphone_open']));
    expect(journal.entries, isNot(contains('microphone_published')),
        reason: 'published once connected');

    host.room.connectGate.open();
    await joining;
    await settle();
    expect(journal.before('connected', 'microphone_published'), isTrue);
  });

  test(
      'the session gets a future that completes once the microphone is '
      'published', () async {
    host.room.microphoneGate = Gate();
    await join().run();

    var completed = false;
    unawaited(host.microphonePublished!.then((_) => completed = true));
    await settle();
    expect(journal.entries, contains('session'));
    expect(completed, isFalse, reason: 'the capture is still opening');

    host.room.microphoneGate.open();
    await host.microphonePublished;
    expect(journal.before('session', 'microphone_published'), isTrue);
  });

  test("in a phone's browser the microphone still opens before the membership",
      () async {
    host.phoneBrowser = true;

    await join().run();
    await settle();

    expect(journal.before('microphone_open', 'membership_write'), isTrue);
    expect(journal.only({'microphone_open'}), hasLength(1),
        reason: 'the one opened early is the one published');
    expect(journal.before('connected', 'microphone_published'), isTrue);
  });

  group('without the power to send the call membership', () {
    setUp(() => host.allowed = false);
    tearDown(() => intl.Intl.defaultLocale = null);

    test('the join is refused before anything is sent', () async {
      var requests = 0;
      var leftPrevious = false;
      final tokens = CallTokenService(client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }));

      await expectLater(
          join(tokens: tokens)
              .run(leavePrevious: () async => leftPrevious = true),
          throwsA(isA<CallJoinException>().having((e) => e.message, 'message',
              'Your role in this channel does not let you join its calls')));

      expect(journal.entries, isEmpty, reason: 'no request of any kind');
      expect(requests, 0);
      expect(leftPrevious, isFalse, reason: 'the call we are in stays');
    });

    test('and is told so in Portuguese', () async {
      await initializeMessages('pt');
      intl.Intl.defaultLocale = 'pt';

      await expectLater(
          join().run(),
          throwsA(isA<CallJoinException>().having((e) => e.message, 'message',
              'Seu cargo neste canal não permite entrar nas chamadas dele')));
      expect(journal.entries, isEmpty);
    });
  });

  test('a connection that fails takes back the membership and the microphone',
      () async {
    host.room.connectError = StateError('no SFU');

    await expectLater(join().run(), throwsStateError);
    await settle();

    expect(journal.before('connect', 'membership_clear'), isTrue);
    expect(host.room.disposed, isTrue);
    expect(host.room.microphones.single.stopped, isTrue,
        reason: 'the capture prepared during the connection is closed');
    expect(journal.entries, isNot(contains('microphone_published')));
  });

  test(
      "in a phone's browser a connection that fails closes the microphone "
      'opened before it', () async {
    host.phoneBrowser = true;
    host.room.connectError = StateError('no SFU');

    await expectLater(join().run(), throwsStateError);
    await settle();

    expect(journal.before('microphone_open', 'membership_write'), isTrue);
    expect(host.room.microphones.single.stopped, isTrue,
        reason: 'the early capture is closed, not left running');
    expect(journal.entries, contains('membership_clear'));
    expect(host.room.disposed, isTrue);
  });

  test('picking the speakers fails the join, as before, with nothing written',
      () async {
    host.outputError = StateError('no audio device');

    await expectLater(join().run(), throwsStateError);
    await settle();

    expect(journal.entries, isNot(contains('membership_write')));
    expect(journal.entries, isNot(contains('connect')));
  });
}
