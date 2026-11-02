// Trim editor for a soundboard import: the source's waveform with a
// selection the admin drags. Dragging a handle past
// SoundboardConstraints.maxDurationMs pulls the other handle along, so the
// selection can never be longer than a stored sound may be. While the
// selection is previewed, a playhead shows where it is.
//
// Pure Flutter so it behaves the same on web.
import 'dart:math' as math;

import 'package:rooster/client/components/soundboard/soundboard_constraints.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SoundboardTrimEditor extends StatefulWidget {
  final int durationMs;

  /// Loudest sample per equal slice of the source, 0..1. Null draws a flat
  /// line (nothing could decode the audio).
  final List<double>? peaks;

  final int startMs;
  final int endMs;
  final void Function(int startMs, int endMs) onChanged;

  /// Where the preview is playing, in the same time as [startMs], or null.
  final int? playheadMs;

  const SoundboardTrimEditor({
    super.key,
    required this.durationMs,
    required this.peaks,
    required this.startMs,
    required this.endMs,
    required this.onChanged,
    this.playheadMs,
  });

  static const double height = 64;

  static String get labelSoundboardTrim => Intl.message("Trim",
      name: "labelSoundboardTrim",
      desc: "Heading over the waveform where a space admin picks the part of "
          "an audio file or link that becomes a soundboard sound");

  static String labelSoundboardTrimLength(String length) => Intl.message(
      "Length $length",
      name: "labelSoundboardTrimLength",
      args: [length],
      desc: "Under the soundboard trim editor: how long the selected part is, "
          "in seconds with the unit (\"3.25 s\")");

  static String labelSoundboardTrimRange(
          String start, String end, String total, String max) =>
      Intl.message(
          "$start – $end of $total · drag the edges to cut the start or the "
          "end, the middle to move it (max $max)",
          name: "labelSoundboardTrimRange",
          args: [start, end, total, max],
          desc: "Under the soundboard trim editor: where the selection starts "
              "and ends in the audio shown, how long that audio is, how to "
              "change the selection by dragging, and the longest a sound may "
              "be. Every value is in seconds with the unit (\"1.50 s\")");

  /// Selection after moving one edge to [ms], keeping it between
  /// [SoundboardConstraints.minDurationMs] and
  /// [SoundboardConstraints.maxDurationMs] long and inside the source.
  static (int, int) moveEdge(
      {required int durationMs,
      required int startMs,
      required int endMs,
      required bool start,
      required int ms}) {
    const minLength = SoundboardConstraints.minDurationMs;
    const maxLength = SoundboardConstraints.maxDurationMs;
    final length = math.min(minLength, durationMs);
    if (start) {
      final s = ms.clamp(0, durationMs - length);
      final e =
          endMs.clamp(s + length, math.min<int>(s + maxLength, durationMs));
      return (s, e);
    }
    final e = ms.clamp(length, durationMs);
    final s = startMs.clamp(math.max<int>(0, e - maxLength), e - length);
    return (s, e);
  }

  @override
  State<SoundboardTrimEditor> createState() => _SoundboardTrimEditorState();
}

enum _Drag { start, end, window }

class _SoundboardTrimEditorState extends State<SoundboardTrimEditor> {
  static const _handleGrabPx = 14.0;

  _Drag? _drag;

  /// For [_Drag.window]: where the pointer grabbed, relative to startMs.
  int _grabOffsetMs = 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final length = widget.endMs - widget.startMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelLow(SoundboardTrimEditor.labelSoundboardTrim),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => _begin(d.localPosition.dx, width),
            onHorizontalDragUpdate: (d) => _update(d.localPosition.dx, width),
            onHorizontalDragEnd: (_) => _drag = null,
            onHorizontalDragCancel: () => _drag = null,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: SizedBox(
                width: width,
                height: SoundboardTrimEditor.height,
                child: CustomPaint(
                  painter: _WaveformPainter(
                    peaks: widget.peaks,
                    start: widget.startMs / widget.durationMs,
                    end: widget.endMs / widget.durationMs,
                    playhead: widget.playheadMs == null
                        ? null
                        : widget.playheadMs! / widget.durationMs,
                    selected: colors.primary,
                    unselected: colors.outlineVariant,
                    background: colors.surfaceContainerHighest,
                    handle: colors.onSurface,
                  ),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
        Row(
          children: [
            tiamat.Text.label(SoundboardTrimEditor.labelSoundboardTrimLength(
                _seconds(length))),
            const SizedBox(width: 8),
            Flexible(
              child: tiamat.Text.labelLow(
                  SoundboardTrimEditor.labelSoundboardTrimRange(
                      _seconds(widget.startMs),
                      _seconds(widget.endMs),
                      _seconds(widget.durationMs),
                      _seconds(SoundboardConstraints.maxDurationMs))),
            ),
          ],
        ),
      ],
    );
  }

  int _msAt(double x, double width) =>
      (x / width * widget.durationMs).round().clamp(0, widget.durationMs);

  void _begin(double x, double width) {
    final startX = widget.startMs / widget.durationMs * width;
    final endX = widget.endMs / widget.durationMs * width;
    final toStart = (x - startX).abs();
    final toEnd = (x - endX).abs();
    if (math.min(toStart, toEnd) <= _handleGrabPx) {
      _drag = toStart <= toEnd ? _Drag.start : _Drag.end;
    } else if (x > startX && x < endX) {
      _drag = _Drag.window;
      _grabOffsetMs = _msAt(x, width) - widget.startMs;
    } else {
      // Outside the selection: move the nearer edge there.
      _drag = toStart <= toEnd ? _Drag.start : _Drag.end;
      _update(x, width);
    }
  }

  void _update(double x, double width) {
    final drag = _drag;
    if (drag == null) return;
    final ms = _msAt(x, width);
    if (drag == _Drag.window) {
      final length = widget.endMs - widget.startMs;
      final start = (ms - _grabOffsetMs).clamp(0, widget.durationMs - length);
      widget.onChanged(start, start + length);
      return;
    }
    final (start, end) = SoundboardTrimEditor.moveEdge(
        durationMs: widget.durationMs,
        startMs: widget.startMs,
        endMs: widget.endMs,
        start: drag == _Drag.start,
        ms: ms);
    widget.onChanged(start, end);
  }

  /// With the language's decimal separator ("1.50 s", "1,50 s").
  static String _seconds(int ms) =>
      '${NumberFormat('0.00').format(ms / 1000)} s';
}

class _WaveformPainter extends CustomPainter {
  final List<double>? peaks;
  final double start;
  final double end;
  final double? playhead;
  final Color selected;
  final Color unselected;
  final Color background;
  final Color handle;

  _WaveformPainter({
    required this.peaks,
    required this.start,
    required this.end,
    this.playhead,
    required this.selected,
    required this.unselected,
    required this.background,
    required this.handle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = background);

    final startX = start * size.width;
    final endX = end * size.width;
    canvas.drawRect(Rect.fromLTRB(startX, 0, endX, size.height),
        Paint()..color = selected.withValues(alpha: 0.15));

    final mid = size.height / 2;
    final peaks = this.peaks;
    if (peaks == null || peaks.isEmpty) {
      canvas.drawLine(
          Offset(0, mid), Offset(size.width, mid), Paint()..color = unselected);
    } else {
      final loudest = peaks.reduce(math.max);
      final scale = loudest > 0 ? 1 / loudest : 0.0;
      final barWidth = size.width / peaks.length;
      for (var i = 0; i < peaks.length; i++) {
        final x = (i + 0.5) * barWidth;
        final h = math.max(1.0, peaks[i] * scale * (size.height / 2 - 4));
        canvas.drawLine(
          Offset(x, mid - h),
          Offset(x, mid + h),
          Paint()
            ..color = x >= startX && x <= endX ? selected : unselected
            ..strokeWidth = math.max(1.0, barWidth * 0.6),
        );
      }
    }

    final handlePaint = Paint()
      ..color = handle
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final x in [startX, endX]) {
      final cx = x.clamp(1.5, size.width - 1.5);
      canvas.drawLine(Offset(cx, 2), Offset(cx, size.height - 2), handlePaint);
    }

    final playhead = this.playhead;
    if (playhead != null) {
      final x = (playhead * size.width).clamp(1.0, size.width - 1.0);
      canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = selected
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.peaks != peaks ||
      old.start != start ||
      old.end != end ||
      old.playhead != playhead ||
      old.selected != selected ||
      old.unselected != unselected ||
      old.background != background ||
      old.handle != handle;
}
