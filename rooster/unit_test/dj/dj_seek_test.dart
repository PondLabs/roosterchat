// The DJ drags the seek bar's thumb to move the song, also while the audio
// runs dry for a moment (the bar used to switch off then).
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/components/dj/dj_models.dart';
import 'package:rooster/client/components/dj/dj_session.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/client/member.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/dj/dj_booth_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import 'dj_fakes.dart';

class _Member implements Member {
  @override
  final String identifier;
  _Member(this.identifier);
  @override
  String get displayName => identifier.split(':').first.substring(1);
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => Colors.teal;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room implements Room {
  @override
  Member getMemberOrFallback(String id) => _Member(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements Client {
  @override
  Room? getRoom(String identifier) => _Room();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements VoipSession {
  @override
  Client get client => _Client();
  @override
  String get roomId => '!r:x';
  @override
  List<VoipStream> get streams => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets('dragging the thumb seeks the song', (tester) async {
    late FakeEngine engine;
    final dj = DjSession(
      transport: FakeCall().join('@dj:x:D1'),
      caps: const DjCaps(canDj: true, platform: 'linux'),
      selfUserId: djUserIdOf('@dj:x:D1'),
      engineFactory: () => engine = FakeEngine('@dj:x:D1'),
      resolver: FakeResolver(),
      tickInterval: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 250),
    )..start();
    await dj.becomeDj();
    dj.addLinks('https://music.example/a');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(dj.current, isNotNull);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.linux)
          .copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
              width: 380,
              height: 720,
              child: DjBoothPanel(session: _Session(), dj: dj)),
        ),
      ),
    ));
    await tester.pump();

    final bar = find.byType(Slider).first;
    final box = tester.getRect(bar);
    // The thumb sits at the start: grab it and drag it to the middle.
    final gesture = await tester.startGesture(
        Offset(box.left + 4, box.center.dy),
        kind: PointerDeviceKind.mouse);
    final offAt = <int>[];
    for (var i = 1; i <= 10; i++) {
      // Halfway, the audio runs dry for a moment, as a song still
      // downloading does: the drag goes on.
      if (i == 5) engine.starve(true);
      if (i == 7) engine.starve(false);
      await gesture.moveTo(
          Offset(box.left + 4 + (box.width / 2 - 4) * i / 10, box.center.dy));
      await tester.pump(const Duration(milliseconds: 300));
      if (tester.widget<Slider>(bar).onChanged == null) offAt.add(i);
    }
    await gesture.up();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }

    final seeked = engine.status.positionMs;
    await tester.pumpWidget(const SizedBox());
    unawaited(dj.dispose());
    await tester.pump(const Duration(seconds: 3));
    expect(offAt, isEmpty, reason: 'the bar switched off mid-drag');
    expect(seeked, greaterThan(60000));
  });
}
