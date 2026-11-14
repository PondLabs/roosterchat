// The call's stage knows no game: a second activity, registered like any
// game would be, is listed on the shelf, launches onto the stage under its
// own name with its own view, gets the participants' cameras by identity,
// and keeps the strip to the people who do not play when it draws the
// players' videos itself.
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
import 'package:rooster/ui/organisms/call_activity/activity_picker_panel.dart';
import 'package:rooster/ui/organisms/call_activity/activity_requests.dart';
import 'package:rooster/ui/organisms/call_activity/activity_stage.dart';
import 'package:rooster/ui/organisms/call_view/call_view.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const _roomId = '!voice:example.org';
const _me = '@me:example.org';
const _myIdentity = '@me:example.org:DEVICEA';
const _alice = '@alice:example.org';
const _aliceIdentity = '@alice:example.org:ALICE';
const _bobIdentity = '@bob:example.org:BOB';
const _type = MatrixCallActivityComponent.stateEventType;
const _fakeId = 'test.fake_game';

/// The fake game's controller: its stage shows a line, and the camera it
/// finds for each identity it is asked about.
class _FakeController extends ChangeNotifier implements CallActivityController {
  _FakeController(this.call);

  final CallActivityCallContext call;
  Object? startedWith;

  @override
  Future<void> hostStart(Object? options) async {
    startedWith = options;
    await call.session.launch();
  }

  @override
  Widget? buildStage(BuildContext context, {required VoidCallback onLeave}) =>
      Column(children: [
        const Text('FAKE GAME VIEW'),
        for (final identity in [_aliceIdentity, _bobIdentity, '@nobody:x'])
          Text('camera of $identity: ${call.cameraOf(identity)?.streamId}'),
      ]);

  @override
  Future<void> leave() => call.session.leave();

  @override
  Future<void> dispose() async => super.dispose();
}

final List<_FakeController> _controllers = [];

CallActivity _fake({
  bool drawsPlayerVideos = false,
}) =>
    CallActivity(
      id: _fakeId,
      displayName: () => 'Fake Game',
      launchOptions: (_) async => 'the options',
      createController: (call) {
        final controller = _FakeController(call);
        _controllers.add(controller);
        return controller;
      },
      drawsPlayerVideos: drawsPlayerVideos,
    );

class _Stream implements VoipStream {
  _Stream(this.streamId, this.streamOwnerId, this.type);

  @override
  final String streamId;

  @override
  final String streamOwnerId;

  @override
  final VoipStreamType type;

  @override
  String get streamUserId => streamOwnerId.split(':').take(2).join(':');

  @override
  VoipStreamDirection get direction => VoipStreamDirection.incoming;

  @override
  bool get requiresWatching => false;

  @override
  bool get isWatching => true;

  @override
  Stream<void> get onStreamChanged => const Stream.empty();

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) => SizedBox(key: key);

  @override
  double get audiolevel => 0;

  @override
  bool get isMuted => false;

  @override
  bool get isDeafened => false;

  @override
  double? get aspectRatio => 16 / 9;

  @override
  String get stats => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profile implements Profile {
  @override
  String get identifier => _me;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Member implements Member {
  _Member(this.identifier);

  @override
  final String identifier;

  @override
  String get displayName => switch (identifier) {
        _alice => 'Alice',
        _me => 'Me',
        _ => 'Bob',
      };

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.teal;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The homeserver: every state write comes back by sync.
class _SdkClient implements matrix.Client {
  void Function(String type, String key, Map<String, dynamic> content)? echo;

  @override
  String? get userID => _me;

  @override
  Future<String> setRoomStateWithKey(String roomId, String eventType,
      String stateKey, Map<String, Object?> body) async {
    echo?.call(eventType, stateKey, Map.of(body));
    return '\$written';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdkRoom implements matrix.Room {
  @override
  final _SdkClient client = _SdkClient();

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
  final _SdkRoom matrixRoom = _SdkRoom();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MatrixClient {
  _Client(this.room);

  final _Room room;

  @override
  Profile? self = _Profile();

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
  Member getMemberOrFallback(String id) => _Member(id);

  @override
  T? getComponent<T extends RoomComponent>() {
    final component = this.component;
    return component is T ? component as T : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements VoipSession {
  _Session(this.client, this.streams);

  @override
  final Client client;

  @override
  final List<VoipStream> streams;

  @override
  String get roomId => _roomId;

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

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Everyone's camera, and a microphone of bob's that is no camera.
final _streams = <VoipStream>[
  _Stream('my-cam', _myIdentity, VoipStreamType.video),
  _Stream('alice-cam', _aliceIdentity, VoipStreamType.video),
  _Stream('bob-mic', _bobIdentity, VoipStreamType.audio),
  _Stream('bob-cam', _bobIdentity, VoipStreamType.video),
];

void main() {
  late _Client client;
  late _Room room;
  late _MatrixRoom matrixRoom;
  late MatrixCallActivityComponent component;
  late InMemoryActivityCall wire;
  late _Session call;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    _controllers.clear();
    CallActivityRegistry.clear();
    room = _Room();
    client = _Client(room);
    matrixRoom = _MatrixRoom();
    wire = InMemoryActivityCall();
    call = _Session(client, _streams);
    component = MatrixCallActivityComponent(client, matrixRoom,
        clock: HomeserverClock(),
        ownCallTransport: () => wire.join(_myIdentity));
    room.component = component;
    matrixRoom.matrixRoom.client.echo = (type, key, content) {
      final event = matrix.Event(
        type: type,
        eventId: '\$$key-echo',
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

  Future<void> pumpCall(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.linux)
          .copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(body: CallView(call)),
    ));
    await tester.pump();
  }

  /// Alice's client hosts a session of the fake game, [players] in it.
  Future<void> aliceHosts(WidgetTester tester, List<String> players) async {
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
          'activity': _fakeId,
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
        'activity': _fakeId,
        'host': _alice,
        'seq': 1,
        'players': players,
      });
      await _settle();
    });
  }

  Finder inStrip(String streamId) =>
      find.byKey(ValueKey('callView_stripView_$streamId'));

  testWidgets(
      'the shelf lists a second activity beside Sunny Side Putt, and '
      'launching it puts its view and its name on the stage', (tester) async {
    CallActivityRegistry.register(sunnySidePuttActivity());
    CallActivityRegistry.register(_fake());
    CallActivityRequests.showShelf(call);
    await pumpCall(tester);
    await tester.pumpAndSettle();

    final shelf = find.byType(ActivityPickerPanel);
    expect(shelf, findsOneWidget);
    expect(find.descendant(of: shelf, matching: find.text('Sunny Side Putt')),
        findsOneWidget);
    expect(find.descendant(of: shelf, matching: find.text('Fake Game')),
        findsOneWidget);
    expect(find.text(ActivityPickerStrings.launch), findsNWidgets(2));

    // The fake game's Launch: the second row.
    await tester.runAsync(() async {
      await tester.tap(find.text(ActivityPickerStrings.launch).last);
      await tester.pump();
      await _settle();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.byType(ActivityStage), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(ActivityStage), matching: find.text('Fake Game')),
        findsOneWidget,
        reason: "the stage's header names the launched activity");
    expect(find.text('FAKE GAME VIEW'), findsOneWidget,
        reason: "the activity's own view fills the stage");
    expect(find.text('Sunny Side Putt'), findsNothing);
    expect(_controllers.single.startedWith, 'the options',
        reason: 'the launch options reach the host start');
    expect(_controllers.single.call.session.isHost, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("the game finds each participant's camera by identity",
      (tester) async {
    CallActivityRegistry.register(_fake());
    await aliceHosts(tester, [_aliceIdentity, _myIdentity]);
    await pumpCall(tester);

    expect(find.text('FAKE GAME VIEW'), findsOneWidget);
    expect(find.text('camera of $_aliceIdentity: alice-cam'), findsOneWidget);
    expect(find.text('camera of $_bobIdentity: bob-cam'), findsOneWidget,
        reason: "a microphone is not someone's camera");
    expect(find.text('camera of @nobody:x: null'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a game that draws the players leaves the strip to who does not play',
      (tester) async {
    CallActivityRegistry.register(_fake(drawsPlayerVideos: true));
    await aliceHosts(tester, [_aliceIdentity, _myIdentity]);
    await pumpCall(tester);

    expect(find.byType(ActivityStage), findsOneWidget);
    expect(inStrip('bob-cam'), findsOneWidget,
        reason: 'bob does not play: the strip shows him');
    expect(inStrip('alice-cam'), findsNothing);
    expect(inStrip('my-cam'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a game that does not draw them leaves everyone in the strip',
      (tester) async {
    CallActivityRegistry.register(_fake());
    await aliceHosts(tester, [_aliceIdentity, _myIdentity]);
    await pumpCall(tester);

    expect(inStrip('bob-cam'), findsOneWidget);
    expect(inStrip('alice-cam'), findsOneWidget);
    expect(inStrip('my-cam'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
