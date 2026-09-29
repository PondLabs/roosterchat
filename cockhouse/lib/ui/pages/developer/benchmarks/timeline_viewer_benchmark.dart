import 'package:cockhouse/client/client.dart';
import 'package:cockhouse/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:cockhouse/client/matrix/matrix_client.dart';
import 'package:cockhouse/diagnostic/mocks/matrix_client_component_mocks.dart';
import 'package:cockhouse/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:cockhouse/ui/pages/developer/benchmarks/benchmark_utils.dart';
import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart' as matrix;

class BenchmarkTimelineViewer extends StatefulWidget {
  const BenchmarkTimelineViewer({super.key});

  @override
  State<BenchmarkTimelineViewer> createState() =>
      _BenchmarkTimelineViewerState();
}

class _BenchmarkTimelineViewerState extends State<BenchmarkTimelineViewer> {
  Timeline? timeline;

  @override
  void initState() {
    // The timeline arrives after a round trip through the client, so the
    // build that set this up has already been and gone. Without saying so,
    // nothing draws it: the benchmark then scrolled a list that was never
    // there, which is why it had never once passed.
    MatrixClient.create("benchmark").then((client) {
      client.mockComponents();
      client.self = MatrixProfile(client,
          matrix.Profile(userId: '@benchy:matrix.org', displayName: 'benchy'));

      var room = client.createRoomWithData();
      if (!mounted) return;
      setState(() => timeline = room.getBenchmarkTimeline());
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Icon(Icons.chevron_left),
      ),
      body: timeline != null
          ? RoomTimelineWidgetView(
              key: const ValueKey("timeline-viewer-benchmark"),
              timeline: timeline!,
              // doMessageOverlayMenu: false,
            )
          : Container(),
    );
  }
}
