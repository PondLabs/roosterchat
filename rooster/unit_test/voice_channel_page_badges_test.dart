// The voice channel's own page, before joining: it showed an avatar for
// everyone in the call and nothing else. Who is sharing their screen, on
// camera, muted or deafened showed only once inside.
import 'dart:async';

import 'package:rooster/client/components/activities/activities_component.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:rooster/utils/image_or_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class _Member implements Member {
  _Member(this.identifier, this.displayName);

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.teal;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Activities implements ActivitiesComponent {
  final RoomActivitySession call = RoomActivitySession(
      participants: {},
      application: 'm.call',
      thirdparty: false,
      icon: ImageOrIcon(icon: Icons.call));

  final StreamController<void> changed = StreamController.broadcast(sync: true);

  @override
  List<RoomActivitySession> getSessions() => [call];

  @override
  Stream<void> get onSessionsChanged => changed.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements Room {
  final _Activities activities = _Activities();

  @override
  final String identifier = '!hangout:example.org';

  @override
  bool get isE2EE => false;

  @override
  T? getComponent<T extends RoomComponent>() =>
      activities is T ? activities as T : null;

  @override
  Member getMemberOrFallback(String id) =>
      _Member(id, id.substring(1, id.indexOf(':')));

  @override
  Future<Member> fetchMember(String id) async => getMemberOrFallback(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Voip implements VoipRoomComponent {
  @override
  final _Room room = _Room();

  @override
  VoipSession? get currentSession => null;

  @override
  List<String> getCurrentParticipants() =>
      room.activities.call.participants.toList();

  @override
  Stream<void> get onParticipantsChanged => const Stream.empty();

  @override
  Future<String?> getCallServerUrl() async => 'livekit.example.org';

  @override
  Future<void> clearStaleOwnMembership() async {}

  @override
  bool get canJoinCall => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Voip voip;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    voip = _Voip();
  });

  void inCall(String name,
      {Set<LiveMedia> media = const {}, Set<VoiceState>? voice, bool? dj}) {
    final id = '@$name:example.org';
    final call = voip.room.activities.call;
    call.participants.add(id);
    if (media.isNotEmpty) call.liveMedia[id] = media;
    if (voice != null) call.voiceState[id] = voice;
    if (dj != null) call.djPlaying[id] = dj;
  }

  Future<void> show(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.linux)
          .copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(body: VoipRoomView(voip)),
    ));
    await tester.pump();
  }

  Finder onTile(String name, Finder what) => find.descendant(
      of: find.byKey(ValueKey('voipRoomView_participant_@$name:example.org')),
      matching: what);

  testWidgets('who is live, on camera, muted or deafened shows before joining',
      (tester) async {
    inCall('alice', media: {LiveMedia.screen}, voice: {VoiceState.muted});
    inCall('bob',
        media: {LiveMedia.camera},
        voice: {VoiceState.muted, VoiceState.deafened});
    inCall('carol', voice: const {});

    await show(tester, const Size(900, 700));

    expect(onTile('alice', find.text('alice')), findsOneWidget);
    expect(onTile('alice', find.text('LIVE')), findsOneWidget);
    expect(onTile('alice', find.byIcon(Icons.mic_off_rounded)), findsOneWidget);
    expect(onTile('bob', find.byIcon(Icons.videocam_rounded)), findsOneWidget);
    expect(
        onTile('bob', find.byIcon(Icons.headset_off_rounded)), findsOneWidget);
    expect(onTile('carol', find.text('carol')), findsOneWidget);
    expect(onTile('carol', find.text('LIVE')), findsNothing);
    expect(onTile('carol', find.byType(Icon)), findsNothing);
  });

  testWidgets('a mute made while the page is open shows without a new member',
      (tester) async {
    inCall('alice');
    await show(tester, const Size(900, 700));
    expect(onTile('alice', find.byIcon(Icons.mic_off_rounded)), findsNothing);

    voip.room.activities.call.voiceState['@alice:example.org'] = {
      VoiceState.muted
    };
    voip.room.activities.changed.add(null);
    await tester.pump();

    expect(onTile('alice', find.byIcon(Icons.mic_off_rounded)), findsOneWidget);
  });

  testWidgets('a full call fits a phone, live badges included', (tester) async {
    for (var i = 1; i <= 16; i++) {
      inCall('guest$i',
          media: {if (i == 3) LiveMedia.screen},
          voice: {if (i.isEven) VoiceState.muted},
          dj: i == 5 ? true : null);
    }

    // A foldable's cover screen. Any overflow fails the test.
    await show(tester, const Size(344, 700));

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.byIcon(Icons.mic_off_rounded), findsNWidgets(8));
    // The DJ's record keeps spinning: stop it with the page.
    await tester.pumpWidget(const SizedBox());
  });
}
