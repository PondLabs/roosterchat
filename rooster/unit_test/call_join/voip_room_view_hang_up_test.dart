// A voice channel's page and the join it asked for. Leaving the page before
// the join is done does not stop it: someone who clicks Join and walks to a
// text channel still ends up in the call. A join hung up (another voice
// channel joined, or the call left) is not a failure: no "Could not join
// the call" dialog.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import 'fakes.dart';

void main() {
  late Journal journal;
  late FakeHost host;
  late MatrixVoipRoomComponent voip;
  late void Function() realPrefetch;
  late void Function(VoipRoomComponent) realWarmUp;
  var rooms = 0;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    realPrefetch = VoipRoomView.prefetchVoiceDsp;
    realWarmUp = VoipRoomView.warmUpCall;
    VoipRoomView.prefetchVoiceDsp = () {};
    VoipRoomView.warmUpCall = (_) {};
  });

  tearDown(() {
    VoipRoomView.prefetchVoiceDsp = realPrefetch;
    VoipRoomView.warmUpCall = realWarmUp;
  });

  /// The channel and its join's fakes. Made in the test's own zone: a
  /// future completed outside it (a gate opened in setUp) runs what awaits
  /// it on the real event loop, which the test's clock does not drive.
  void channel() {
    journal = Journal();
    // A room of its own per test: what CallMembershipWrites holds is
    // shared by every test of the file.
    final roomId = '!page-${rooms++}:example.org';
    host = FakeHost(journal)..roomId = roomId;
    final sdk = FakeSdkClient();
    final client = FakeMatrixClient(sdk);
    voip = MatrixVoipRoomComponent(client, FakeMatrixRoom(roomId, sdk));
    voip.backend =
        FakeBackend(SessionHost(host, client), fakeTokenService(journal));
  }

  Widget app(Widget body) => MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux)
            .copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(body: body),
      );

  /// Lets the join's requests and steps run, on the test's clock.
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  /// What [future] gave, after a [flush]. Fails the test when it is still
  /// running then, rather than wait for it: on the test's clock an await
  /// that never ends hangs the run instead of timing out.
  Future<T> done<T>(WidgetTester tester, Future<T> future) async {
    var finished = false;
    Object? error;
    T? value;
    future.then((v) {
      value = v;
      finished = true;
    }, onError: (Object e) {
      error = e;
      finished = true;
    });
    await flush(tester);
    expect(finished, isTrue, reason: 'still running');
    if (error != null) throw error!;
    return value as T;
  }

  /// Opens the page and clicks Join: the join starts on the next frame.
  Future<void> openAndJoin(WidgetTester tester) async {
    await tester.pumpWidget(app(VoipRoomView(voip)));
    await tester.pump();
    await tester.tap(find.text(CommonStrings.promptJoin));
    await flush(tester);
  }

  final errorDialog = find.text(VoipRoomView.errorCallJoinFailed);

  testWidgets(
      'leaving the page while the join connects: the join goes on and ends '
      'connected, with nothing thrown', (tester) async {
    channel();
    host.room.connectGate = Gate();
    await openAndJoin(tester);
    expect(journal.entries, containsAll(['membership_written', 'connect']));

    await tester.pumpWidget(app(const Text('Home')));
    await flush(tester);
    host.room.connectGate.open();
    await flush(tester);

    expect(journal.entries, contains('session'));
    expect(journal.entries, isNot(contains('membership_clear')));
    expect(host.membership, isTrue);
    expect(voip.currentSession?.state, VoipState.connected);
    expect(errorDialog, findsNothing);
    expect(tester.takeException(), isNull,
        reason: 'the session arriving does not set the closed page state');
    unawaited(voip.currentSession!.hangUpCall());
    await flush(tester);
  });

  testWidgets(
      'a join hung up while the page stays open (another channel was '
      'joined) shows no dialog, and Join is there again', (tester) async {
    channel();
    host.room.connectGate = Gate();
    await openAndJoin(tester);

    voip.hangUpJoin();
    host.room.connectGate.open();
    await flush(tester);

    expect(errorDialog, findsNothing);
    expect(host.membership, isFalse);
    expect(find.text(CommonStrings.promptJoin), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a join that fails still opens the dialog', (tester) async {
    channel();
    host.room.connectError = StateError('no SFU');
    await openAndJoin(tester);
    await flush(tester);

    expect(errorDialog, findsOneWidget);
    expect(host.membership, isFalse);
  });

  testWidgets('leaving the page once the call is joined does not leave it',
      (tester) async {
    channel();
    await tester.pumpWidget(app(VoipRoomView(voip)));
    await tester.pump();
    final session = await done(tester, voip.joinCall()) as FakeVoipSession;

    await tester.pumpWidget(app(const Text('Home')));
    await tester.pump();
    expect(session.state, VoipState.connected);
    expect(host.membership, isTrue);
    unawaited(session.hangUpCall());
    await flush(tester);
  });

  testWidgets(
      "the call's server answering after the page closed is not an error",
      (tester) async {
    channel();
    final answer = Completer<List<Uri>>();
    (voip.backend as FakeBackend).fociAnswer = answer.future;
    await tester.pumpWidget(app(VoipRoomView(voip)));
    await tester.pump();

    await tester.pumpWidget(app(const Text('Home')));
    answer.complete([Uri.parse('https://jwt.example.org')]);
    await flush(tester);
    expect(tester.takeException(), isNull);
  });
}
