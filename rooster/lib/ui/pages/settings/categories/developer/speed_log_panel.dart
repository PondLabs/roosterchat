import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/diagnostic/speed_log/speed_summary.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Settings > Developer: p50 and p95 of every operation in the speed log
/// and of each of its steps, and the button that copies the speed report.
/// See docs/speed-log.md.
class SpeedLogPanel extends StatefulWidget {
  const SpeedLogPanel({this.log, super.key});

  /// The app's log when null.
  final SpeedLog? log;

  static String get labelDeveloperSpeedLog => Intl.message("Speed log",
      name: "labelDeveloperSpeedLog",
      desc: "Title of the Developer settings section that shows how long "
          "sending a message, each sync and other network operations took "
          "on this device");

  static String get labelDeveloperSpeedLogEmpty =>
      Intl.message("Nothing timed yet",
          name: "labelDeveloperSpeedLogEmpty",
          desc: "In Developer settings > Speed log, before any operation has "
              "been timed");

  static String labelDeveloperSpeedLogSamples(int howMany) =>
      Intl.plural(howMany,
          one: "1 sample",
          other: "$howMany samples",
          name: "labelDeveloperSpeedLogSamples",
          args: [howMany],
          desc: "In Developer settings > Speed log: how many timings an "
              "operation or one of its steps has");

  static String labelDeveloperSpeedLogPercentiles(String p50, String p95) =>
      Intl.message("p50 $p50 ms · p95 $p95 ms",
          name: "labelDeveloperSpeedLogPercentiles",
          args: [p50, p95],
          desc: "In Developer settings > Speed log: the median (p50) and the "
              "95th percentile (p95) of how long an operation or a step took, "
              "in milliseconds");

  static String labelDeveloperSpeedLogNotTimed(int howMany) => Intl.plural(
      howMany,
      one: "1 not timed",
      other: "$howMany not timed",
      name: "labelDeveloperSpeedLogNotTimed",
      args: [howMany],
      desc: "In Developer settings > Speed log: how many times a step could "
          "not be timed by the app (it is left out, not guessed)");

  static String get promptDeveloperCopySpeedReport =>
      Intl.message("Copy speed report",
          name: "promptDeveloperCopySpeedReport",
          desc: "Button in Developer settings > Speed log that copies the "
              "speed report, a text with the timings and no message content, "
              "to paste into an issue");

  static String get messageDeveloperSpeedReportCopied =>
      Intl.message("Speed report copied",
          name: "messageDeveloperSpeedReportCopied",
          desc: "Shown after the speed report was copied from Developer "
              "settings > Speed log");

  @override
  State<SpeedLogPanel> createState() => _SpeedLogPanelState();
}

class _SpeedLogPanelState extends State<SpeedLogPanel> {
  SpeedLog get log => widget.log ?? SpeedLog.instance;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final operations = summarizeSpeedLog(log);
    return ExpansionTile(
      title: tiamat.Text.labelEmphasised(SpeedLogPanel.labelDeveloperSpeedLog),
      backgroundColor: colors.surfaceContainerLow,
      collapsedBackgroundColor: colors.surfaceContainerLow,
      // The log keeps filling while the app runs: read it again on open.
      onExpansionChanged: (_) => setState(() {}),
      children: [
        if (operations.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child:
                tiamat.Text.labelLow(SpeedLogPanel.labelDeveloperSpeedLogEmpty),
          ),
        for (final operation in operations) ...[
          _row(context, operation.name, operation.total, 0, indent: false),
          for (final step in operation.steps)
            _row(context, step.name, step.timing, step.unavailable,
                indent: true),
        ],
        Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: tiamat.Button(
              text: SpeedLogPanel.promptDeveloperCopySpeedReport,
              onTap: _copyReport,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copyReport() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: buildSpeedReport(log)));
    messenger?.showSnackBar(SnackBar(
        content: Text(SpeedLogPanel.messageDeveloperSpeedReportCopied)));
  }

  Widget _row(
      BuildContext context, String name, Percentiles? timing, int notTimed,
      {required bool indent}) {
    final colors = Theme.of(context).colorScheme;
    final details = [
      SpeedLogPanel.labelDeveloperSpeedLogSamples(timing?.count ?? 0),
      if (timing != null)
        SpeedLogPanel.labelDeveloperSpeedLogPercentiles(
            _ms(timing.p50), _ms(timing.p95)),
      if (notTimed > 0) SpeedLogPanel.labelDeveloperSpeedLogNotTimed(notTimed),
    ];
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(indent ? 32 : 20, 2, 20, 2),
      child: Wrap(
        spacing: 16,
        runSpacing: 2,
        children: [
          // Not translated: the operation and step names are identifiers from
          // the code, the same as in the copied report.
          tiamat.Text.labelLow(name,
              color: indent ? colors.onSurfaceVariant : colors.onSurface),
          for (final detail in details)
            tiamat.Text.labelLow(detail, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }

  /// Milliseconds in the app's language: "1,5" in Portuguese.
  static String _ms(Duration d) {
    final ms = d.inMicroseconds / 1000;
    return NumberFormat(ms < 10 ? '0.#' : '0').format(ms);
  }
}
