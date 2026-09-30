// The listener's music slider. The booth swaps its idle and playing layouts
// when a DJ starts or a song changes, which removes a slider being dragged:
// it is never let go, and the level it was dragged to has to be kept anyway,
// or the next song plays at the old one.
import 'package:cockhouse/client/components/voip/voip_session.dart';
import 'package:cockhouse/client/components/voip/voip_stream.dart';
import 'package:cockhouse/main.dart';
import 'package:cockhouse/ui/organisms/dj/dj_booth_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class _Session implements VoipSession {
  @override
  List<VoipStream> get streams => const [];

  @override
  bool get isDeafened => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.djMusicVolume.set(1.0);
  });

  testWidgets('a slider removed mid-drag keeps the level it was dragged to',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
          body: Center(child: DjMusicVolume(session: _Session(), width: 300))),
    ));

    final slider = find.byType(Slider);
    final gesture = await tester
        .startGesture(tester.getTopLeft(slider) + const Offset(8, 8));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(preferences.djMusicVolume.value, 1.0,
        reason: 'saved once, when let go');
    expect(liveDjMusicVolume.value, lessThan(0.3));

    // A DJ starts: the layout holding the slider goes away.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    await gesture.up();

    expect(preferences.djMusicVolume.value, lessThan(0.3));
    expect(liveDjMusicVolume.value, isNull);
  });

  testWidgets('the slider is long enough to set a level precisely',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(body: Center(child: DjMusicVolume(session: _Session()))),
    ));

    expect(
        tester.getSize(find.byType(Slider)).width, greaterThanOrEqualTo(160));
  });

  testWidgets("in the booth it takes the booth's whole width", (tester) async {
    await tester.binding.setSurfaceSize(const Size(380, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
          body: Center(child: DjMusicVolume(session: _Session(), width: null))),
    ));

    expect(tester.getSize(find.byType(Slider)).width, greaterThan(250));
    expect(find.text('100%'), findsOneWidget);
  });
}
