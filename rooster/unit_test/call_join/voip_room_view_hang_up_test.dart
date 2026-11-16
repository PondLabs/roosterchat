// A voice channel's page and the join it asked for. Leaving the page before
// the join is done hangs the join up: it takes back the membership it sent,
// and no session comes of it. A join hung up (by the page, or by a join of
// another channel) is not a failure: no "Could not join the call" dialog.
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

  /// Opens the page and clicks Join: the join starts on the next frame.
  Future<void> openAndJoin(WidgetTester tester) async {
    await tester.pumpWidget(app(VoipRoomView(voip)));
    await tester.pump();
    await tester.tap(find.text(CommonStrings.promptJoin));
    await flush(tester);
  }

  final errorDialog = find.text(VoipRoomView.errorCallJoinFailed);

  testWidgets(
      'leaving the page while the join connects hangs the join up: its '
      'membership is taken back, no session, no dialog', (tester) async {
    channel();
    host.room.connectGate = Gate();
    await openAndJoin(tester);
    expect(journal.entries, containsAll(['membership_written', 'connect']));

    await tester.pumpWidget(app(const Text('Home')));
    host.room.connectGate.open();
    await flush(tester);

    expect(journal.entries, contains('membership_clear'));
    expect(host.membership, isFalse);
    expect(journal.entries, isNot(contains('session')));
    expect(host.room.disposed, isTrue);
    expect(voip.currentSession, isNull);
    expect(errorDialog, findsNothing);
    expect(tester.takeException(), isNull);
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
    final joining = voip.joinCall();
    await flush(tester);
    final session = await joining as FakeVoipSession;

    await tester.pumpWidget(app(const Text('Home')));
    await tester.pump();
    expect(session.state, VoipState.connected);
    expect(host.membership, isTrue);
    unawaited(session.hangUpCall());
    await flush(tester);
  });

  testWidgets(
      "T3.2's INVERSE 8 through the page: the old join's write is in flight "
      'past the 10 s when the page closes, a new join gets in and its call '
      'is left, then the old write lands: no membership, no session',
      (tester) async {
    channel();
    final oldWrite = Gate();
    host.membershipGate = oldWrite;
    await openAndJoin(tester);
    expect(journal.entries, containsAll(['membership_write', 'connected']));

    // Leaving the page hangs the join up; its write is still in flight.
    await tester.pumpWidget(app(const Text('Home')));
    await flush(tester);

    host.membershipGate = Gate()..open();
    host.room = FakeLivekitRoom(journal);
    final joining = voip.joinCall();
    // It waits for the old join, 10 s at most, on the test's clock.
    await tester.pump(const Duration(seconds: 11));
    await flush(tester);
    final session = await joining as FakeVoipSession;
    expect(host.membership, isTrue);

    final hangingUp = session.hangUpCall();
    await flush(tester);
    await hangingUp;
    expect(host.membership, isFalse);

    oldWrite.open();
    await flush(tester);

    expect(journal.lastIndexOf('membership_clear'),
        greaterThan(journal.lastIndexOf('membership_written')),
        reason: 'the old join cleared its late write');
    expect(host.membership, isFalse, reason: 'no membership without session');
    expect(journal.count('session'), 1);
    expect(voip.currentSession?.state ?? VoipState.ended, VoipState.ended);
  });
}
