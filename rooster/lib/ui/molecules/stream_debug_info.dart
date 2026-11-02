// Developer mode: a call tile's stream info (encryption and its type). It
// sat over the top left of everyone's video for good; a click moves it to
// the next corner, and every tile follows the corner picked last.
import 'dart:async';

import 'package:rooster/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class StreamDebugInfo extends StatefulWidget {
  const StreamDebugInfo(this.stats, {super.key});

  final String stats;

  static String get tooltipStreamDebugInfoMove => Intl.message(
      "Click to move it to the next corner",
      name: "tooltipStreamDebugInfoMove",
      desc: "Tooltip of the stream info box developer mode shows over a call "
          "tile; clicking it moves the box to the tile's next corner");

  /// The corners in the order a click goes round them.
  static const corners = {
    "topLeft": Alignment.topLeft,
    "topRight": Alignment.topRight,
    "bottomRight": Alignment.bottomRight,
    "bottomLeft": Alignment.bottomLeft,
  };

  @override
  State<StreamDebugInfo> createState() => _StreamDebugInfoState();
}

class _StreamDebugInfoState extends State<StreamDebugInfo> {
  late final StreamSubscription<String> _sub;

  @override
  void initState() {
    super.initState();
    _sub = preferences.streamDebugInfoCorner.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  String get _corner {
    final saved = preferences.streamDebugInfoCorner.value;
    return StreamDebugInfo.corners.containsKey(saved) ? saved : "topLeft";
  }

  void _moveOn() {
    final names = StreamDebugInfo.corners.keys.toList();
    preferences.streamDebugInfoCorner
        .set(names[(names.indexOf(_corner) + 1) % names.length]);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: StreamDebugInfo.corners[_corner]!,
      child: Tooltip(
        message: StreamDebugInfo.tooltipStreamDebugInfoMove,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _moveOn,
            child: Container(
              decoration: BoxDecoration(
                color: ColorScheme.of(context).surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: tiamat.Text.labelLow(widget.stats),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
