import 'package:rooster/diagnostic/diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class CumulativeDiagnosticsWidget extends StatefulWidget {
  const CumulativeDiagnosticsWidget(
      {required this.diagnostics, this.title, super.key});

  final CumulativeDiagnostics diagnostics;

  /// What the group is called on screen; the diagnostics' own name, which
  /// the logs use, when not given.
  final String? title;

  @override
  State<CumulativeDiagnosticsWidget> createState() =>
      _CumulativeDiagnosticsWidgetState();
}

class _CumulativeDiagnosticsWidgetState
    extends State<CumulativeDiagnosticsWidget> {
  late List<CumulativeMeasurement> measurements;

  String labelDeveloperDiagnosticsCalls(int howMany) => Intl.plural(howMany,
      one: "1 call",
      other: "$howMany calls",
      name: "labelDeveloperDiagnosticsCalls",
      args: [howMany],
      desc: "In Developer settings > Performance: how many times a measured "
          "piece of code ran");

  String labelDeveloperDiagnosticsAverage(int milliseconds) => Intl.message(
      "${milliseconds}ms avg",
      name: "labelDeveloperDiagnosticsAverage",
      args: [milliseconds],
      desc: "In Developer settings > Performance: how long a measured piece "
          "of code took on average, in milliseconds");

  String labelDeveloperDiagnosticsTotal(int milliseconds) => Intl.message(
      "${milliseconds}ms total",
      name: "labelDeveloperDiagnosticsTotal",
      args: [milliseconds],
      desc: "In Developer settings > Performance: how long a measured piece "
          "of code took in all, in milliseconds");

  @override
  void initState() {
    measurements = widget.diagnostics.measurements.values.toList();
    measurements.sort(
      (a, b) => b.totalDuration.compareTo(a.totalDuration),
    );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
        title: tiamat.Text.labelEmphasised(
            widget.title ?? widget.diagnostics.name),
        initiallyExpanded: false,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        collapsedBackgroundColor:
            Theme.of(context).colorScheme.surfaceContainerLow,
        children: measurements
            .mapIndexed((e, i) => Container(
                  color: i % 2 == 0
                      ? Theme.of(context).colorScheme.surfaceDim
                      : Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                            child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 2, 8, 2),
                          child: tiamat.Text.labelLow(
                            e.name,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        )),
                        Flexible(
                          child: tiamat.Text.labelLow(
                            [
                              labelDeveloperDiagnosticsCalls(e.numCalls),
                              labelDeveloperDiagnosticsAverage(
                                  (e.totalDuration.inMilliseconds / e.numCalls)
                                      .round()),
                              labelDeveloperDiagnosticsTotal(
                                  e.totalDuration.inMilliseconds),
                            ].join("   -   "),
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        )
                      ],
                    ),
                  ),
                ))
            .toList());
  }
}
