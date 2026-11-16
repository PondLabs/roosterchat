// The warm-up before the click, from the screen: a voice channel's page
// warms its call when it opens, and the pointer or the keyboard focus
// resting on a join button (the page's Join, Who's around's "Join call")
// warms it once per rest. A pointer only passing over warms nothing, and
// none of it joins.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/live_voice_channels.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/home_screen/whos_around_section.dart';
import 'package:rooster/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class _Client implements Client {
  @override
  final String identifier = 'client';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Member implements Member {
  _Member(this.identifier);

  @override
  final String identifier;

  @override
  String get displayName => identifier;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.teal;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements Room {
  _Room(this.voip);

  final _Voip voip;

  @override
  final Client client = _Client();

  @override
  final String identifier = '!hangout:example.org';

  @override
  String get displayName => 'Hangout';

  @override
  bool get isE2EE => false;

  @override
  ImageProvider? get avatar => null;

  @override
  Member getMemberOrFallback(String id) => _Member(id);

  @override
  Future<Member> fetchMember(String id) async => _Member(id);

  @override
  T? getComponent<T extends RoomComponent>() => voip is T ? voip as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Voip implements VoipRoomComponent {
  late final _Room room = _Room(this);

  int joins = 0;

  @override
  VoipSession? get currentSession => null;

  @override
  List<String> getCurrentParticipants() => const [];

  @override
  Stream<void> get onParticipantsChanged => const Stream.empty();

  @override
  Future<String?> getCallServerUrl() async => 'livekit.example.org';

  @override
  Future<void> clearStaleOwnMembership() async {}

  @override
  bool get canJoinCall => true;

  @override
  Future<VoipSession?> joinCall() {
    joins++;
    return Completer<VoipSession?>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Source implements LiveVoiceChannelsSource {
  _Source(Room room)
      : channels = [
          LiveVoiceChannel(
              room: room,
              space: null,
              participants: const ['@alice:example.org'],
              liveMedia: const {},
              djPlaying: const {},
              ours: false)
        ],
        voiceChannels = [room];

  @override
  final List<LiveVoiceChannel> channels;

  @override
  final List<Room> voiceChannels;

  @override
  Stream<void> get onChanged => const Stream.empty();

  @override
  Space? spaceOf(Room room) => null;
}

void main() {
  late _Voip voip;
  late List<String> warmUps;
  late void Function(VoipRoomComponent) realWarmUp;
  late void Function() realPrefetch;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    voip = _Voip();
    warmUps = [];
    realWarmUp = VoipRoomView.warmUpCall;
    realPrefetch = VoipRoomView.prefetchVoiceDsp;
    VoipRoomView.warmUpCall = (voip) => warmUps.add(voip.room.identifier);
    VoipRoomView.prefetchVoiceDsp = () {};
  });

  tearDown(() {
    VoipRoomView.warmUpCall = realWarmUp;
    VoipRoomView.prefetchVoiceDsp = realPrefetch;
  });

  Widget app(Widget body) => MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux)
            .copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 320, height: 600, child: body))),
      );

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    return gesture;
  }

  const dwell = Duration(milliseconds: 150);

  group("a voice channel's page", () {
    Finder join() => find.text(CommonStrings.promptJoin);

    testWidgets('warms the call when it opens, once', (tester) async {
      await tester.pumpWidget(app(VoipRoomView(voip)));
      expect(warmUps, ['!hangout:example.org']);
      await tester.pump();
      await tester.pumpWidget(app(VoipRoomView(voip)));
      expect(warmUps, hasLength(1), reason: 'not per build');
      expect(voip.joins, 0);
    });

    testWidgets('the pointer resting on Join warms it once', (tester) async {
      await tester.pumpWidget(app(VoipRoomView(voip)));
      await tester.pump();
      warmUps.clear();

      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(join()));
      await tester.pump(dwell ~/ 2);
      expect(warmUps, isEmpty, reason: 'not before it rests');
      await tester.pump(dwell);
      expect(warmUps, hasLength(1));

      // Still resting, moving inside the button: no more.
      await pointer.moveBy(const Offset(2, 1));
      await tester.pump(const Duration(seconds: 2));
      expect(warmUps, hasLength(1));
      expect(voip.joins, 0, reason: 'resting is not clicking');
    });

    testWidgets('the focus resting on Join warms it once', (tester) async {
      await tester.pumpWidget(app(VoipRoomView(voip)));
      await tester.pump();
      warmUps.clear();

      Focus.of(tester.element(join())).requestFocus();
      await tester.pump();
      expect(warmUps, isEmpty);
      await tester.pump(dwell);
      expect(warmUps, hasLength(1));
      await tester.pump(const Duration(seconds: 2));
      expect(warmUps, hasLength(1));
      expect(voip.joins, 0);
    });

    testWidgets('a pointer passing over Join warms nothing', (tester) async {
      await tester.pumpWidget(app(VoipRoomView(voip)));
      await tester.pump();
      warmUps.clear();

      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(join()));
      await tester.pump(dwell ~/ 3);
      await pointer.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 1));
      expect(warmUps, isEmpty);
    });
  });

  group("Who's around", () {
    late List<Room> warmed;

    Future<void> show(WidgetTester tester) async {
      warmed = [];
      await tester.pumpWidget(app(SingleChildScrollView(
        child: WhosAroundSection(
          source: _Source(voip.room),
          onOpen: (_) {},
          onJoin: (_) => voip.joins++,
          onWarmUp: warmed.add,
        ),
      )));
      await tester.pump();
    }

    Finder joinCall() => find.text(WhosAroundSection.labelJoinCall);

    testWidgets('the pointer resting on "Join call" warms that call once',
        (tester) async {
      await show(tester);
      expect(warmed, isEmpty, reason: 'listing a channel warms nothing');

      final pointer = await mouse(tester);
      // The row around the button warms nothing.
      await pointer.moveTo(tester.getTopLeft(find.text('Hangout')));
      await tester.pump(const Duration(seconds: 1));
      expect(warmed, isEmpty);

      await pointer.moveTo(tester.getCenter(joinCall()));
      await tester.pump(dwell ~/ 2);
      expect(warmed, isEmpty);
      await tester.pump(dwell);
      expect(warmed, [voip.room]);
      await pointer.moveBy(const Offset(1, 1));
      await tester.pump(const Duration(seconds: 2));
      expect(warmed, hasLength(1));
      expect(voip.joins, 0);
    });

    testWidgets('the focus resting on "Join call" warms that call once',
        (tester) async {
      await show(tester);
      Focus.of(tester.element(joinCall())).requestFocus();
      await tester.pump();
      await tester.pump(dwell);
      expect(warmed, [voip.room]);
      await tester.pump(const Duration(seconds: 2));
      expect(warmed, hasLength(1));
      expect(voip.joins, 0);
    });

    testWidgets('the real warm-up of a channel that is not Matrix does nothing',
        (tester) async {
      // WhosAroundSection.warmUp, as the app has it: a fake component is
      // not a Matrix voice channel, which alone has a token service.
      WhosAroundSection.warmUp(voip.room);
      expect(voip.joins, 0);
    });
  });
}
