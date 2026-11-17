// Moving ourselves to another voice channel joins it. When another channel
// is joined while that join runs, the join is hung up: nothing failed, so
// no "Could not move them" dialog. A move that really fails still says so.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:rooster/client/client_manager.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager.dart';
import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager_stub.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_call_moves_component.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/voice_channel_members/call_member_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import 'fakes.dart';

class _Sdk extends FakeSdkClient {
  @override
  final CachedStreamController<matrix.ToDeviceEvent> onToDeviceEvent =
      CachedStreamController();
}

class _Client extends FakeMatrixClient {
  _Client(super.matrixClient);
  MatrixCallMovesComponent? moves;

  @override
  T? getComponent<T extends Component>() => moves is T ? moves as T : null;
}

class _Room extends FakeMatrixRoom {
  _Room(super.roomId, super.client, this.owner);
  final _Client owner;
  MatrixVoipRoomComponent? voip;

  @override
  MatrixClient get client => owner;

  @override
  T? getComponent<T extends RoomComponent>() => voip is T ? voip as T : null;
}

typedef _Channel = (_Room, FakeHost);

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    // ignore: invalid_use_of_visible_for_testing_member
    AudioProcessingManager.debugInstance = UnsupportedAudioProcessingManager();
    clientManager = ClientManager();
  });

  tearDown(() {
    clientManager = null;
    // ignore: invalid_use_of_visible_for_testing_member
    AudioProcessingManager.debugInstance = null;
  });

  /// Channels A, B and C of one account, and a page to show dialogs on.
  /// Made in the test's own zone, so their gates run on its clock.
  Future<(BuildContext, _Channel, _Channel, _Channel)> setUpChannels(
      WidgetTester tester) async {
    final sdk = _Sdk();
    final client = _Client(sdk);
    client.moves = MatrixCallMovesComponent(client);
    final calls = clientManager!.callManager;

    _Channel channel(String id) {
      final journal = Journal();
      final host = FakeHost(journal)..roomId = id;
      final room = _Room(id, sdk, client);
      final voip = MatrixVoipRoomComponent(client, room);
      voip.backend = FakeBackend(
          SessionHost(host, client, calls: calls), fakeTokenService(journal));
      room.voip = voip;
      return (room, host);
    }

    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      theme: ThemeData(platform: TargetPlatform.linux)
          .copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(body: Builder(builder: (c) {
        context = c;
        return const Text('Home');
      })),
    ));
    return (
      context,
      channel('!move-a:example.org'),
      channel('!move-b:example.org'),
      channel('!move-c:example.org'),
    );
  }

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    // A dialog's opening animation.
    await tester.pump(const Duration(seconds: 1));
  }

  final moveError = find.text(CallMemberMenu.errorCallMemberMove);

  testWidgets(
      'we move ourselves to B, then join C while that join runs: B is hung '
      'up, and no error is shown', (tester) async {
    final (context, (a, _), (b, hostB), (c, hostC)) =
        await setUpChannels(tester);
    hostB.room.connectGate = Gate();
    unawaited(CallMemberMenu.move(context, a, '@me:example.org', b));
    await flush(tester);
    expect(hostB.journal.entries, contains('connect'));

    unawaited(c
        .getComponent<VoipRoomComponent>()!
        .joinCall()
        .then<void>((_) {}, onError: (_) {}));
    await flush(tester);
    hostB.room.connectGate.open();
    await flush(tester);

    expect(hostB.membership, isFalse);
    expect(hostC.membership, isTrue);
    expect(moveError, findsNothing);
    expect(find.textContaining('CallJoinHungUp'), findsNothing);
  });

  testWidgets('a move whose join fails shows the error once', (tester) async {
    final (context, (a, _), (b, hostB), _) = await setUpChannels(tester);
    hostB.room.connectError = StateError('no SFU');
    unawaited(CallMemberMenu.move(context, a, '@me:example.org', b));
    await flush(tester);

    expect(hostB.membership, isFalse);
    expect(moveError, findsOneWidget);
  });
}
