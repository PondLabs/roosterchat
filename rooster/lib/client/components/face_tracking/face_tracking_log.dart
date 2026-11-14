import 'dart:convert';

import 'face_tracker.dart';

/// The record of a run of the demonstration, in the lines
/// tools/face_tracking/measure.py reads: every frame a tracker analysed,
/// with its frame code, and every frame the interface drew.
class FaceTrackingLog {
  final _lines = <String>[];
  final _clock = Stopwatch()..start();

  double get _now => _clock.elapsedMicroseconds / 1000;

  /// One analysed frame of [video]. Frames without a frame code are left
  /// out: nothing to compare them with.
  void anchor(String video, FaceObservation observation) {
    final code = observation.frameCode;
    if (code == null) return;
    final anchor = observation.anchor;
    final size = observation.videoSize;
    _lines.add(jsonEncode({
      'type': 'anchor',
      'video': video,
      'code': code,
      't': _now,
      'face': anchor == null
          ? null
          : {
              'x': anchor.center.dx / size.width,
              'y': anchor.center.dy / size.height,
              'width': anchor.width / size.width,
              'angle': anchor.angle,
            },
    }));
  }

  /// One frame drawn by the interface.
  void frame() => _lines.add(jsonEncode({'type': 'frame', 't': _now}));

  String toJsonLines() => _lines.isEmpty ? '' : '${_lines.join('\n')}\n';
}
