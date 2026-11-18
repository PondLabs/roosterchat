/// "Copy speed report" says on its own button that it copied, for 2 s,
/// wherever the panel is shown: on a settings page with no Scaffold below
/// the app's ScaffoldMessenger (the desktop settings), inside a Scaffold,
/// and on a phone at 280 and 320 px in English and Portuguese. A copy that
/// fails does not say it copied. Runs on the VM and in Chrome.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/ui/pages/settings/categories/developer/speed_log_panel.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../device_verification/verify_device_layout.dart'
    show loadFontsAndLanguages, phoneScreen;

class _NoFrames implements FrameSource {
  @override
  void listen(Duration Function() clock,
      void Function(List<FrameSample> batch) onBatch) {}
  @override
  void cancel() {}
}

/// One text send of 100 ms whose request took 10 ms.
SpeedLog speedLog() {
  var now = Duration.zero;
  final log = SpeedLog(frames: _NoFrames(), clock: () => now);
  final span = log.startSpan(SpeedOperation.textSend);
  now += const Duration(milliseconds: 10);
  span.mark(SpeedStep.request);
  now += const Duration(milliseconds: 90);
  span.finish();
  return log;
}

/// The clipboard: what was copied, or a [PlatformException] when [fail].
List<String> clipboard(WidgetTester tester, {bool fail = false}) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      if (fail) throw PlatformException(code: 'clipboard', message: 'busy');
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

/// The panel open, in a [Scaffold] or, like the desktop settings, only on
/// a [Material] under the app's ScaffoldMessenger.
Future<void> openPanel(WidgetTester tester, SpeedLog log,
    {required bool scaffold, Key? boundary}) async {
  final panel = SingleChildScrollView(child: SpeedLogPanel(log: log));
  await tester.pumpWidget(RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      theme: ThemeDark.theme,
      debugShowCheckedModeBanner: false,
      home: scaffold ? Scaffold(body: panel) : Material(child: panel),
    ),
  ));
  await tester.tap(find.text(SpeedLogPanel.labelDeveloperSpeedLog));
  await tester.pumpAndSettle();
}

/// Taps the copy button, whatever it says, and lets the copy finish
/// without moving the clock.
Future<void> tapCopy(WidgetTester tester) async {
  await tester.tap(find.byType(ElevatedButton));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(loadFontsAndLanguages);
  tearDown(() => intl.Intl.defaultLocale = null);

  for (final scaffold in [false, true]) {
    final where = scaffold ? 'inside a Scaffold' : 'with no Scaffold';
    testWidgets('the button says it copied for 2 s, $where', (tester) async {
      final copied = clipboard(tester);
      final log = speedLog();
      await openPanel(tester, log, scaffold: scaffold);

      await tapCopy(tester);

      expect(tester.takeException(), isNull);
      expect(copied, [buildSpeedReport(log)]);
      expect(find.text(SpeedLogPanel.messageDeveloperSpeedReportCopied),
          findsOneWidget);
      expect(find.text(SpeedLogPanel.promptDeveloperCopySpeedReport),
          findsNothing);

      // Copying again keeps it for 2 s from the second tap.
      await tester.pump(const Duration(milliseconds: 1500));
      await tapCopy(tester);
      expect(copied, hasLength(2));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text(SpeedLogPanel.messageDeveloperSpeedReportCopied),
          findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(SpeedLogPanel.promptDeveloperCopySpeedReport),
          findsOneWidget);
      expect(find.text(SpeedLogPanel.messageDeveloperSpeedReportCopied),
          findsNothing);
    });
  }

  testWidgets('a copy that fails does not say it copied', (tester) async {
    clipboard(tester, fail: true);
    await openPanel(tester, speedLog(), scaffold: false);

    await tapCopy(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(SpeedLogPanel.messageDeveloperSpeedReportCopied),
        findsNothing);
    expect(find.text(SpeedLogPanel.promptDeveloperCopySpeedReport),
        findsOneWidget);
  });

  testWidgets('closing the panel while it says copied leaves no timer',
      (tester) async {
    clipboard(tester);
    await openPanel(tester, speedLog(), scaffold: false);
    await tapCopy(tester);

    await tester.pumpWidget(const SizedBox());
    // A timer left running fails the test when it ends.
  });

  for (final locale in ['en', 'pt']) {
    for (final width in [280.0, 320.0]) {
      final label = '${width.toInt()} px ($locale)';
      testWidgets('whole before and after the copy at $label', (tester) async {
        phoneScreen(tester, width);
        intl.Intl.defaultLocale = locale;
        clipboard(tester);
        await openPanel(tester, speedLog(), scaffold: false);
        _expectWholeTexts(tester, '$label before',
            SpeedLogPanel.promptDeveloperCopySpeedReport);

        await tapCopy(tester);
        _expectWholeTexts(tester, '$label after',
            SpeedLogPanel.messageDeveloperSpeedReportCopied);
        if (locale == 'pt') {
          expect(SpeedLogPanel.messageDeveloperSpeedReportCopied,
              'Relatório de velocidade copiado');
        }
        await tester.pump(const Duration(seconds: 2));
      });
    }
  }
}

/// No text cut or wider than its box, and [button] shown.
void _expectWholeTexts(WidgetTester tester, String label, String button) {
  expect(tester.takeException(), isNull, reason: '$label: overflow');
  for (final p
      in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
    final text = p.text.toPlainText();
    expect(p.didExceedMaxLines, isFalse, reason: '$label: "$text" is cut');
    expect(p.size.width <= p.constraints.maxWidth + 0.5, isTrue,
        reason: '$label: "$text" is wider than its box');
  }
  expect(find.text(button), findsOneWidget, reason: '$label: "$button"');
}
