// A voice channel's page: Join waited a fixed 100 ms before starting, so
// the spinner showed; it now waits for the frame that draws it. On the web
// the DSP's wasm was fetched when the first call started; it is now fetched
// when a voice channel's page opens, and never before.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/components/room_component.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip_room/voip_room_component.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class _Room implements Room {
  @override
  final String identifier = '!hangout:example.org';

  @override
  bool get isE2EE => false;

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Voip implements VoipRoomComponent {
  @override
  final _Room room = _Room();

  int joins = 0;
  final Completer<VoipSession?> joined = Completer();

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
    return joined.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Voip voip;
  late int prefetches;
  late void Function() realPrefetch;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    voip = _Voip();
    prefetches = 0;
    realPrefetch = VoipRoomView.prefetchVoiceDsp;
    VoipRoomView.prefetchVoiceDsp = () => prefetches++;
  });

  tearDown(() => VoipRoomView.prefetchVoiceDsp = realPrefetch);

  Widget app(Widget body) => MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux)
            .copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(body: body),
      );

  testWidgets('the DSP is fetched when a voice channel opens, not before',
      (tester) async {
    await tester.pumpWidget(app(const Text('Home')));
    expect(prefetches, 0, reason: 'nothing at startup');

    await tester.pumpWidget(app(VoipRoomView(voip)));
    expect(prefetches, 1);

    await tester.pump();
    await tester.pumpWidget(app(VoipRoomView(voip)));
    expect(prefetches, 1, reason: 'once per page opened, not per build');
    expect(voip.joins, 0, reason: 'looking at a channel joins nothing');
  });

  testWidgets('Join starts after the frame that draws the spinner, not 100 ms',
      (tester) async {
    await tester.pumpWidget(app(VoipRoomView(voip)));
    await tester.pump();

    await tester.tap(find.text(CommonStrings.promptJoin));
    expect(voip.joins, 0, reason: 'the spinner is drawn first');

    await tester.pump();
    expect(voip.joins, 1, reason: 'one frame later, no fixed delay');

    voip.joined.complete(null);
    await tester.pump();
  });
}
