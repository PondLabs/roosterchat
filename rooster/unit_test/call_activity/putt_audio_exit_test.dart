// Report (2026-11-07): the music did not stop when leaving the activity. The
// game's sound is built the first time the game draws and was only released
// in CallView.dispose(), so leaving the activity left the loop playing until
// the whole call view went away. _exitActivity() releases it now, through
// the game's controller, which owns the sound.
//
// The rest goes through the call view the way people do: Sunny Side Putt
// launched from the shelf through its descriptor's hooks (and not launched
// when the sheet is dismissed), joined from the call's invite, and the
// stage drawing frames while the sound is still going down. Launches the
// call view must refuse leave no session behind, and say so.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_transport.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/client/matrix/components/call_activity/matrix_call_activity_component.dart';
import 'package:rooster/client/matrix/homeserver_clock.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/call_activity/activity_join_pill.dart';
import 'package:rooster/ui/organisms/call_activity/activity_picker_panel.dart';
import 'package:rooster/ui/organisms/call_activity/activity_requests.dart';
import 'package:rooster/ui/organisms/call_activity/activity_stage.dart';
import 'package:rooster/ui/organisms/call_view/call_view.dart';
import 'package:rooster/client/components/sunny_side_putt/core/rules.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_audio.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_launch_options.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_match.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_session.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const _roomId = '!voice:example.org';
const _me = '@me:example.org';
const _myIdentity = '@me:example.org:DEVICEA';
const _alice = '@alice:example.org';
const _aliceIdentity = '@alice:example.org:ALICE';
const _type = MatrixCallActivityComponent.stateEventType;

const _puttId = 'chat.commet.putt';

/// The game's sound, watched instead of heard.
class _FakeAudio extends PuttAudio {
  /// How many times the game asked for its sound.
  int builds = 0;
  int disposals = 0;

  /// The real sound takes its players down one by one, over platform
  /// channels: the release is not instant. A test holds it open here.
  Future<void> released = Future.value();

  @override
  Future<void> preload() async {}

  @override
  Future<void> dispose() async {
    disposals++;
    await released;
    await super.dispose();
  }
}

class _Profile implements Profile {
  _Profile(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Member implements Member {
  @override
  String get identifier => _alice;

  @override
  String get displayName => 'Alice';

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.teal;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The homeserver: every state write is kept, and comes back by sync.
class _SdkClient implements matrix.Client {
  final List<(String, String, Map<String, dynamic>)> writes = [];
  void Function(String type, String key, Map<String, dynamic> content)? echo;

  @override
  String? get userID => _me;

  @override
  Future<String> setRoomStateWithKey(String roomId, String eventType,
      String stateKey, Map<String, Object?> body) async {
    writes.add((eventType, stateKey, Map.of(body)));
    echo?.call(eventType, stateKey, Map.of(body));
    return '\$written';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdkRoom implements matrix.Room {
  _SdkRoom(this.client);

  @override
  final _SdkClient client;

  @override
  final String id = _roomId;

  @override
  final Map<String, Map<String, matrix.StrippedStateEvent>> states = {};

  @override
  bool canChangeStateEvent(String action) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MatrixRoom implements MatrixRoom {
  @override
  final String identifier = _roomId;

  @override
  final _SdkRoom matrixRoom = _SdkRoom(_SdkClient());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MatrixClient {
  _Client(this.room);

  final _Room room;

  @override
  Profile? self = _Profile(_me);

  @override
  Room? getRoom(String identifier) => room;

  @override
  List<Space> get spaces => const [];

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements Room {
  MatrixCallActivityComponent? component;

  @override
  String get displayName => 'Hangout';

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.teal;

  @override
  Member getMemberOrFallback(String id) => _Member();

  @override
  T? getComponent<T extends RoomComponent>() {
    final component = this.component;
    return component is T ? component as T : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements VoipSession {
  _Session(this.client);

  @override
  final Client client;

  @override
  String get roomId => _roomId;

  @override
  List<VoipStream> get streams => const [];

  @override
  VoipState get state => VoipState.connected;

  @override
  Stream<void> get onStateChanged => const Stream.empty();

  @override
  Stream<void> get onUpdateVolumeVisualizers => const Stream.empty();

  @override
  Future<void> updateStats() async {}

  @override
  bool get supportsScreenshare => true;

  @override
  bool get isMicrophoneMuted => false;

  @override
  bool get isDeafened => false;

  @override
  bool get isCameraEnabled => false;

  @override
  bool get isSharingScreen => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The game alice's client hosts, as its session's state carries it: the
/// match is adopted from this, and the game draws.
Map<String, Object?> _hostedGame() {
  final config = PuttSessionController.buildConfig(
      const PuttLaunchOptions(mode: GameMode.casual));
  final match = PuttMatch(config: config, localPlayerId: _aliceIdentity)
    ..boot();
  final game = {
    'config': {
      'mode': config.mode.name,
      'seed': config.seed,
      'courses': [for (final course in config.courses) course.id],
      'physics': puttPhysicsVersion,
      'courseHash': puttCatalogHash,
    },
    'engine': match.engine.toJson(),
  };
  match.dispose();
  return game;
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Client client;
  late _Room room;
  late _MatrixRoom matrixRoom;
  late MatrixCallActivityComponent component;
  late InMemoryActivityCall wire;
  late _FakeAudio audio;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    CallActivityRegistry.clear();
    // The game's real descriptor, its sound swapped for one we watch.
    audio = _FakeAudio();
    CallActivityRegistry.register(sunnySidePuttActivity(audio: () {
      audio.builds++;
      return audio;
    }));
    room = _Room();
    client = _Client(room);
    matrixRoom = _MatrixRoom();
    wire = InMemoryActivityCall();
    component = MatrixCallActivityComponent(client, matrixRoom,
        clock: HomeserverClock(),
        ownCallTransport: () => wire.join(_myIdentity));
    room.component = component;
    matrixRoom.matrixRoom.client.echo = (type, key, content) {
      final event = matrix.Event(
        type: type,
        eventId: '\$$key-${matrixRoom.matrixRoom.client.writes.length}',
        senderId: _me,
        stateKey: key,
        originServerTs: DateTime.now(),
        room: matrixRoom.matrixRoom,
        content: content,
      );
      (matrixRoom.matrixRoom.states[type] ??= {})[key] = event;
      scheduleMicrotask(() => component.onSync(matrix.JoinedRoomUpdate(
          timeline: matrix.TimelineUpdate(events: [event]))));
    };
  });

  tearDown(CallActivityRegistry.clear);

  /// A session's state as someone else's client left it.
  void stateOf(String sessionId, {required String host}) {
    final key = MatrixCallActivityComponent.stateKeyOf(sessionId);
    final event = matrix.Event(
      type: _type,
      eventId: '\$$key',
      senderId: host,
      stateKey: key,
      originServerTs: DateTime.now(),
      room: matrixRoom.matrixRoom,
      content: {
        'activity': _puttId,
        'host': host,
        'created': DateTime.now().millisecondsSinceEpoch,
        'expires': MatrixCallActivityComponent.expires.inMilliseconds,
      },
    );
    (matrixRoom.matrixRoom.states[_type] ??= {})[key] = event;
    component.onSync(matrix.JoinedRoomUpdate(
        timeline: matrix.TimelineUpdate(events: [event])));
  }

  testWidgets('leaving the activity releases the game sound', (tester) async {
    await tester.runAsync(() async {
      // A session we hold a seat in is in the room state.
      stateOf(_myIdentity, host: _me);
      await _settle();
      final aliceSide = wire.join(_aliceIdentity);
      addTearDown(aliceSide.dispose);
      await aliceSide.send({
        't': 'state',
        'id': _myIdentity,
        'activity': _puttId,
        'host': _alice,
        'seq': 1,
        'players': [_myIdentity],
        'game': _hostedGame(),
      });
      await _settle();
    });

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.linux)
          .copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(body: CallView(_Session(client))),
    ));
    // The game draws: its own ticker never settles, a few frames.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    // The stage is up: we are in the activity, and its sound is alive.
    expect(find.byType(ActivityStage), findsOneWidget,
        reason: 'the activity stage must be on screen');
    expect(find.byType(SunnySidePuttView), findsOneWidget,
        reason: 'the game must draw on the stage');
    expect(audio.builds, 1, reason: 'the game draws with its sound');
    expect(find.byIcon(Icons.close_rounded), findsOneWidget,
        reason: 'the stage must offer its exit');
    expect(audio.disposals, 0);

    // The exit path awaits the session's leave, which rides the wire: run
    // it out in real time, then let the view rebuild.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip(ActivityStageStrings.leave));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();

    expect(find.byType(ActivityStage), findsNothing,
        reason: 'the stage must be gone once we left the activity');
    expect(audio.disposals, 1,
        reason: 'leaving the activity must stop the looping music');

    await tester.pumpWidget(const SizedBox());
  });

  Future<void> pumpCall(WidgetTester tester, {bool shelf = false}) async {
    final call = _Session(client);
    if (shelf) CallActivityRequests.showShelf(call);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.linux)
          .copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(body: CallView(call)),
    ));
  }

  /// Alice's client hosts a session of [activity], [players] in it.
  Future<void> aliceHosts(WidgetTester tester,
      {String activity = _puttId,
      required List<String> players,
      Map<String, Object?>? game}) async {
    await tester.runAsync(() async {
      final key = MatrixCallActivityComponent.stateKeyOf(_aliceIdentity);
      final event = matrix.Event(
        type: _type,
        eventId: '\$$key',
        senderId: _alice,
        stateKey: key,
        originServerTs: DateTime.now(),
        room: matrixRoom.matrixRoom,
        content: {
          'activity': activity,
          'host': _alice,
          'created': DateTime.now().millisecondsSinceEpoch,
          'expires': MatrixCallActivityComponent.expires.inMilliseconds,
        },
      );
      (matrixRoom.matrixRoom.states[_type] ??= {})[key] = event;
      component.onSync(matrix.JoinedRoomUpdate(
          timeline: matrix.TimelineUpdate(events: [event])));
      await _settle();
      final aliceSide = wire.join(_aliceIdentity);
      addTearDown(aliceSide.dispose);
      await aliceSide.send({
        't': 'state',
        'id': _aliceIdentity,
        'activity': activity,
        'host': _alice,
        'seq': 1,
        'players': players,
        if (game != null) 'game': game,
      });
      await _settle();
    });
  }

  /// Taps [finder] and lets the launch or join it starts run out.
  Future<void> tapThrough(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await tester.pump();
      await _settle();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets('a frame drawn while the game sound is still going down',
      (tester) async {
    await tester.runAsync(() async {
      stateOf(_myIdentity, host: _me);
      await _settle();
      final aliceSide = wire.join(_aliceIdentity);
      addTearDown(aliceSide.dispose);
      await aliceSide.send({
        't': 'state',
        'id': _myIdentity,
        'activity': _puttId,
        'host': _alice,
        'seq': 1,
        'players': [_myIdentity, _aliceIdentity],
        'game': _hostedGame(),
      });
      await _settle();
    });
    final release = Completer<void>();
    audio.released = release.future;
    await pumpCall(tester);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.byType(SunnySidePuttView), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip(ActivityStageStrings.leave));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(audio.disposals, 1, reason: 'the release has started');
    // Alice still plays, so our leaving changes the session's roster, the
    // room's activity component says so, and the call view draws a frame
    // on its own while the sound is still going down.
    await tester.pump();
    final error = tester.takeException();
    release.complete();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    await tester.pump();
    expect(error, isNull,
        reason: 'no frame may throw while the stage is on its way out');
    expect(find.byType(ActivityStage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sunny Side Putt launches from the shelf through its hooks',
      (tester) async {
    await pumpCall(tester, shelf: true);
    await tester.pumpAndSettle();
    expect(find.byType(ActivityPickerPanel), findsOneWidget);
    await tester.tap(find.text(ActivityPickerStrings.launch));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget,
        reason: "the game's launch sheet must open");

    await tapThrough(tester, find.text('Start'));

    expect(find.byType(ActivityStage), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(ActivityStage),
            matching: find.text('Sunny Side Putt')),
        findsOneWidget);
    expect(find.byType(SunnySidePuttView), findsOneWidget,
        reason: 'the launched game must draw');
    expect(component.ownSession?.isHost, isTrue);
    expect(audio.builds, 1);
    await tester.pumpWidget(const SizedBox());
    expect(audio.disposals, 1,
        reason: 'the call view going away releases the sound');
  });

  testWidgets('dismissing the launch sheet launches nothing', (tester) async {
    await pumpCall(tester, shelf: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text(ActivityPickerStrings.launch));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Start'), findsNothing);
    expect(find.byType(ActivityStage), findsNothing);
    expect(component.ownSession, isNull);
    expect(matrixRoom.matrixRoom.client.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("Sunny Side Putt is joined from the call's invite",
      (tester) async {
    await aliceHosts(tester, players: [_aliceIdentity], game: _hostedGame());
    await pumpCall(tester);
    await tester.pump();
    expect(find.byType(ActivityJoinPill), findsOneWidget);
    expect(find.text('Alice started Sunny Side Putt'), findsOneWidget);

    await tapThrough(tester, find.text(ActivityJoinPill.join));

    expect(find.byType(ActivityStage), findsOneWidget);
    expect(find.byType(SunnySidePuttView), findsOneWidget,
        reason: 'the joined game must draw');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a descriptor without a controller is not launched: no session is '
      'left behind, and the call says so', (tester) async {
    CallActivityRegistry.clear();
    CallActivityRegistry.register(
        CallActivity(id: 'test.name_only', displayName: () => 'Name Only'));
    await pumpCall(tester, shelf: true);
    await tester.pumpAndSettle();

    await tapThrough(tester, find.text(ActivityPickerStrings.launch));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ActivityStage), findsNothing);
    expect(component.ownSession, isNull,
        reason: 'a launch that fails must not leave a session we host');
    expect(matrixRoom.matrixRoom.client.writes, isEmpty);
    expect(find.text(CallView.messageActivityLaunchFailed), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'launching a game while a session this device cannot run is live '
      'says it could not start', (tester) async {
    const fakeId = 'test.unavailable';
    CallActivityRegistry.register(CallActivity(
      id: fakeId,
      displayName: () => 'Fake Game',
      createController: (call) => throw StateError('must not be built'),
      availability: () => const CallActivityAvailability.unavailable(),
    ));
    await aliceHosts(tester, activity: fakeId, players: [_aliceIdentity]);
    await pumpCall(tester, shelf: true);
    await tester.pumpAndSettle();
    // Only Sunny Side Putt offers Launch; the fake says why it cannot run.
    expect(find.text(ActivityPickerStrings.launch), findsOneWidget);
    await tester.tap(find.text(ActivityPickerStrings.launch));
    await tester.pumpAndSettle();

    await tapThrough(tester, find.text('Start'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ActivityStage), findsNothing);
    expect(find.text(CallView.messageActivityLaunchFailed), findsOneWidget,
        reason: 'a launch that does nothing must say so');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("Sunny Side Putt's stage does not rebuild on each host state",
      (tester) async {
    late CallActivityTransport aliceSide;
    final game = _hostedGame();
    await tester.runAsync(() async {
      stateOf(_myIdentity, host: _me);
      await _settle();
      aliceSide = wire.join(_aliceIdentity);
      addTearDown(aliceSide.dispose);
      await aliceSide.send({
        't': 'state',
        'id': _myIdentity,
        'activity': _puttId,
        'host': _alice,
        'seq': 1,
        'players': [_myIdentity],
        'game': game,
      });
      await _settle();
    });
    await pumpCall(tester);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.byType(SunnySidePuttView), findsOneWidget);
    var stageRebuilds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is ListenableBuilder &&
          element.findAncestorWidgetOfExactType<ActivityStage>() == null &&
          element.findAncestorWidgetOfExactType<CallView>() != null) {
        stageRebuilds++;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    for (var seq = 2; seq <= 6; seq++) {
      await tester.runAsync(() async {
        await aliceSide.send({
          't': 'state',
          'id': _myIdentity,
          'activity': _puttId,
          'host': _alice,
          'seq': seq,
          'players': [_myIdentity],
          'game': game,
        });
        await _settle();
      });
      await tester.pump(const Duration(milliseconds: 40));
    }
    debugOnRebuildDirtyWidget = null;
    expect(stageRebuilds, 0,
        reason: 'a game that does not draw the players needs no rebuild of '
            "the stage when the session's state comes");
    await tester.pumpWidget(const SizedBox());
  });
}
