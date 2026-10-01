// Adding music to the booth is labelled and obvious, for the DJ and for a
// listener wondering how to play something.
import 'dart:async';

import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/components/dj/dj_models.dart';
import 'package:cockhouse/client/components/dj/dj_session.dart';
import 'package:cockhouse/client/components/voip/voip_session.dart';
import 'package:cockhouse/client/components/voip/voip_stream.dart';
import 'package:cockhouse/client/member.dart';
import 'package:cockhouse/main.dart';
import 'package:cockhouse/ui/organisms/dj/dj_booth_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

DjSession _session(FakeCall call, String identity) => DjSession(
      transport: call.join(identity),
      caps: const DjCaps(canDj: true, platform: 'linux'),
      selfUserId: djUserIdOf(identity),
      engineFactory: () => FakeEngine(identity),
      resolver: FakeResolver(),
      tickInterval: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 250),
    )..start();

/// The side panel's width in the call view.
Widget _app(DjSession dj) => MaterialApp(
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
    );

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump();
  }
}

Future<void> _teardown(WidgetTester tester, List<DjSession> sessions) async {
  await tester.pumpWidget(const SizedBox());
  for (final s in sessions) {
    unawaited(s.dispose());
  }
  await _drain(tester);
}

bool _fits(WidgetTester tester, String text) =>
    !tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets('the DJ has labelled, enabled Add music and Choose files buttons',
      (tester) async {
    final dj = _session(FakeCall(), '@dj:x:D1');
    await dj.becomeDj();
    await _drain(tester);
    expect(dj.isDj, isTrue);

    await tester.pumpWidget(_app(dj));
    await tester.pump();

    final add = find.widgetWithText(FilledButton, 'Add music');
    final files = find.widgetWithText(OutlinedButton, 'Choose files…');
    final addEnabled = tester.widget<FilledButton>(add).enabled;
    final filesEnabled = tester.widget<OutlinedButton>(files).enabled;
    final fits = _fits(tester, 'Add music') && _fits(tester, 'Choose files…');
    final hint =
        tester.widget<TextField>(find.byType(TextField)).decoration?.hintText;
    await _teardown(tester, [dj]);

    expect(addEnabled, isTrue);
    expect(filesEnabled, isTrue);
    expect(fits, isTrue, reason: 'labels are cut off in the 380 px booth');
    expect(hint?.toLowerCase(), contains('drop'));
  });

  testWidgets('a listener is told how to start playing music', (tester) async {
    final call = FakeCall();
    final dj = _session(call, '@dj:x:D1');
    final listener = _session(call, '@a:x:A1');
    await dj.becomeDj();
    await _drain(tester);

    await tester.pumpWidget(_app(listener));
    await tester.pump();

    final howTo = find.textContaining('Ask for the decks');
    final found = howTo.evaluate().length;
    final noAdd = find.text('Add music').evaluate().isEmpty;
    await _teardown(tester, [dj, listener]);

    expect(found, greaterThanOrEqualTo(2),
        reason: 'the button and the line saying what it is for');
    expect(noAdd, isTrue);
  });

  testWidgets('free decks offer to take them to play music', (tester) async {
    final dj = _session(FakeCall(), '@a:x:A1');
    await _drain(tester);

    await tester.pumpWidget(_app(dj));
    await tester.pump();

    final take = find.text('Take the decks to play music').evaluate().length;
    await _teardown(tester, [dj]);
    expect(take, 1);
  });
}
