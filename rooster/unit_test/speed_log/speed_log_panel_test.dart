import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/diagnostic/speed_log/speed_summary.dart';
import 'package:rooster/ui/pages/settings/categories/developer/speed_log_panel.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _NoFrames implements FrameSource {
  @override
  void listen(Duration Function() clock,
      void Function(List<FrameSample> batch) onBatch) {}
  @override
  void cancel() {}
}

/// A log on a clock the test moves by hand: 20 text sends of 10, 20... 200
/// ms whose request took 1, 2... 20 ms, one that failed, one sync of 30 s,
/// and a third operation, one voice join of 450 ms whose connection took
/// 300 ms. The panel has no list of operations: it shows whatever the log
/// holds, so the voice join must appear like the other two.
SpeedLog _log() {
  var now = Duration.zero;
  final log = SpeedLog(frames: _NoFrames(), clock: () => now);
  for (var i = 1; i <= 20; i++) {
    final span = log.startSpan(SpeedOperation.textSend);
    now += Duration(milliseconds: i);
    span.mark(SpeedStep.request);
    now += Duration(milliseconds: 9 * i);
    span.unavailable(SpeedStep.echoPainted);
    span.finish();
  }
  final failed = log.startSpan(SpeedOperation.textSend);
  now += const Duration(seconds: 60);
  failed.finish(outcome: SpeedOutcome.failed);

  final sync = log.startSpan(SpeedOperation.sync);
  now += const Duration(milliseconds: 30000);
  sync.mark(SpeedStep.serverWait);
  sync.finish();

  final join = log.startSpan(SpeedOperation.voiceJoin);
  now += const Duration(milliseconds: 150);
  join.mark(SpeedStep.membershipWrite);
  now += const Duration(milliseconds: 300);
  join.mark(SpeedStep.connect);
  join.finish();
  return log;
}

void main() {
  test('p50 and p95 are by nearest rank over the spans that ended ok', () {
    final summary = summarizeSpeedLog(_log());

    expect(summary.map((o) => o.name), ['sync', 'text_send', 'voice_join']);
    final send = summary[1];
    expect(send.finished, 21);
    expect(send.ok, 20);
    expect(send.total!.p50, const Duration(milliseconds: 100));
    expect(send.total!.p95, const Duration(milliseconds: 190));
    final request = send.steps.firstWhere((s) => s.name == SpeedStep.request);
    expect(request.timing!.p50, const Duration(milliseconds: 10));
    expect(request.timing!.p95, const Duration(milliseconds: 19));
    final painted =
        send.steps.firstWhere((s) => s.name == SpeedStep.echoPainted);
    expect(painted.timing, isNull);
    expect(painted.unavailable, 20);

    expect(Percentiles.of([const Duration(milliseconds: 7)])!.p95,
        const Duration(milliseconds: 7));
    expect(Percentiles.of(const []), isNull);
  });

  testWidgets('the panel lists p50 and p95 per operation and copies the report',
      (tester) async {
    final log = _log();
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home:
          Scaffold(body: SingleChildScrollView(child: SpeedLogPanel(log: log))),
    ));
    await tester.tap(find.text(SpeedLogPanel.labelDeveloperSpeedLog));
    await tester.pumpAndSettle();

    // The three operations in the log and a step of each, by their names.
    for (final name in [
      'text_send',
      'sync',
      'voice_join',
      'request',
      'server_wait',
      'connect',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('p50 100 ms · p95 190 ms'), findsOneWidget);
    expect(find.text('p50 10 ms · p95 19 ms'), findsOneWidget);
    expect(find.text('p50 30000 ms · p95 30000 ms'), findsNWidgets(2));
    // The voice join's total and its connect step.
    expect(find.text('p50 450 ms · p95 450 ms'), findsOneWidget);
    expect(find.text('p50 300 ms · p95 300 ms'), findsOneWidget);
    expect(find.text('20 samples'), findsNWidgets(2));
    expect(find.text('20 not timed'), findsOneWidget);

    await tester.tap(find.text(SpeedLogPanel.promptDeveloperCopySpeedReport));
    await tester.pumpAndSettle();

    expect(copied, buildSpeedReport(log));
    expect(copied, contains('text_send ok=20/21 p50=100ms p95=190ms'));
    expect(copied, contains('  request n=20 p50=10ms p95=19ms'));
    expect(copied, contains('  echo_painted n=0 unavailable=20'));
    expect(copied, contains('voice_join ok=1/1 p50=450ms p95=450ms'));
    expect(copied, contains('  connect n=1 p50=300ms p95=300ms'));
    expect(find.text(SpeedLogPanel.messageDeveloperSpeedReportCopied),
        findsOneWidget);
    // The button says so for 2 s.
    await tester.pump(const Duration(seconds: 2));

    // The copied report, for the evidence folder.
    final out = Platform.environment['SPEED_REPORT_OUT'];
    if (out != null) File(out).writeAsStringSync(copied!);
  });

  testWidgets('an empty log says nothing was timed yet', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(body: SpeedLogPanel(log: SpeedLog(frames: _NoFrames()))),
    ));
    await tester.tap(find.text(SpeedLogPanel.labelDeveloperSpeedLog));
    await tester.pumpAndSettle();

    expect(
        find.text(SpeedLogPanel.labelDeveloperSpeedLogEmpty), findsOneWidget);
  });
}
