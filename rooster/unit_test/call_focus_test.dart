// A click on someone live in the sidebar puts them in the middle of the call,
// already playing: asked for because watching someone took the channel, then
// their tile, then "Watch stream".
import 'dart:async';

import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/profile/profile_component.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/call_view/call_focus.dart';
import 'package:rooster/ui/organisms/call_view/call_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const _alice = '@alice:example.org';
const _bob = '@bob:example.org';

class _Stream implements VoipStream {
  _Stream(this.streamId, this.streamUserId, this.type);

  @override
  final String streamId;

  @override
  final String streamUserId;

  @override
  final VoipStreamType type;

  bool watching = false;

  @override
  String get streamOwnerId => streamUserId;

  @override
  VoipStreamDirection get direction => VoipStreamDirection.incoming;

  @override
  bool get requiresWatching => type == VoipStreamType.screenshare;

  @override
  bool get isWatching => !requiresWatching || watching;

  @override
  Future<void> watch() async => watching = true;

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

class _Room implements Room {
  @override
  String get displayName => 'Hangout';

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.teal;

  @override
  Member getMemberOrFallback(String id) => _Member();

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements Client {
  @override
  Room? getRoom(String identifier) => _Room();

  @override
  Profile? get self => null;

  @override
  List<Space> get spaces => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements VoipSession {
  _Session(this.streams);

  @override
  final List<VoipStream> streams;

  @override
  final Client client = _Client();

  @override
  String get roomId => '!hangout:example.org';

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

/// The call's main tile holding [stream], the one with the white border.
Finder _inTheMiddle(VoipStream stream) =>
    find.byKey(ValueKey('callView_mainStreamView_${stream.streamId}'));

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  group('CallFocus.streamOf', () {
    final mic = _Stream('mic', _alice, VoipStreamType.audio);
    final camera = _Stream('camera', _alice, VoipStreamType.video);
    final screen = _Stream('screen', _alice, VoipStreamType.screenshare);
    final screenAudio =
        _Stream('screen-audio', _alice, VoipStreamType.screenshareAudio);
    final bobs = _Stream('bobs', _bob, VoipStreamType.screenshare);

    test('someone showing both opens on their screen', () {
      expect(CallFocus.streamOf([mic, camera, screen, bobs], _alice), screen);
    });

    test('someone on camera opens on it', () {
      expect(CallFocus.streamOf([bobs, mic, camera], _alice), camera);
    });

    test('there is nothing to open of someone only talking', () {
      expect(CallFocus.streamOf([mic, screenAudio, bobs], _alice), isNull);
    });
  });

  test('a request waits for the call view, and is taken once', () {
    final session = _Session([]);
    final other = _Session([]);

    CallFocus.show(session, _alice);
    expect(CallFocus.takeRequest(other), isNull);
    expect(CallFocus.takeRequest(session), _alice);
    expect(CallFocus.takeRequest(session), isNull);
  });

  group('the call view', () {
    Future<void> show(WidgetTester tester, VoipSession session) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux)
            .copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(body: CallView(session)),
      ));
      await tester.pump();
    }

    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('opened by the click: starts on them, playing', (tester) async {
      final screen = _Stream('screen', _alice, VoipStreamType.screenshare);
      final camera = _Stream('camera', _alice, VoipStreamType.video);
      final session = _Session([camera, screen]);

      CallFocus.show(session, _alice);
      await show(tester, session);

      expect(_inTheMiddle(screen), findsOneWidget);
      expect(screen.watching, isTrue);
      await done(tester);
    });

    testWidgets('already open: moves to them, playing', (tester) async {
      final mine = _Stream('bobs', _bob, VoipStreamType.video);
      final screen = _Stream('screen', _alice, VoipStreamType.screenshare);
      final session = _Session([mine, screen]);

      await show(tester, session);
      expect(_inTheMiddle(screen), findsNothing);
      expect(screen.watching, isFalse);

      CallFocus.show(session, _alice);
      await tester.pump();
      await tester.pump();

      expect(_inTheMiddle(screen), findsOneWidget);
      expect(screen.watching, isTrue);
      await done(tester);
    });

    testWidgets("another call's request leaves it alone", (tester) async {
      final screen = _Stream('screen', _alice, VoipStreamType.screenshare);
      final session = _Session([screen]);
      final other = _Session([]);

      await show(tester, session);
      CallFocus.show(other, _alice);
      await tester.pump();
      await tester.pump();

      expect(_inTheMiddle(screen), findsNothing);
      expect(screen.watching, isFalse);
      await done(tester);
    });
  });
}
