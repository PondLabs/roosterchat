import 'package:cockhouse/config/preferences/double_preference.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Gives [child] the width saved in [preference], which the user changes by
/// dragging a thin handle on its right edge. Double-clicking the handle puts
/// the default back.
class ResizableWidth extends StatefulWidget {
  const ResizableWidth({
    required this.preference,
    required this.min,
    required this.max,
    required this.child,
    super.key,
  });

  final DoublePreference preference;
  final double min;
  final double max;
  final Widget child;

  static const handleKey = ValueKey("resizable-width-handle");

  @override
  State<ResizableWidth> createState() => _ResizableWidthState();
}

class _ResizableWidthState extends State<ResizableWidth> {
  late double width = _clamp(widget.preference.value);
  // Measured from where the drag began, so the edge stays under the pointer
  // after being held against min or max.
  double _dragFrom = 0, _dragged = 0;

  double _clamp(double w) => w.clamp(widget.min, widget.max).toDouble();

  void _save(double w) {
    setState(() => width = _clamp(w));
    widget.preference.set(width);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 6,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                key: ResizableWidth.handleKey,
                behavior: HitTestBehavior.opaque,
                // Count the movement before the drag was recognised too, so
                // the edge follows the pointer from where it was pressed.
                dragStartBehavior: DragStartBehavior.down,
                onHorizontalDragStart: (_) {
                  _dragFrom = width;
                  _dragged = 0;
                },
                onHorizontalDragUpdate: (d) {
                  _dragged += d.delta.dx;
                  setState(() => width = _clamp(_dragFrom + _dragged));
                },
                onHorizontalDragEnd: (_) => _save(width),
                onDoubleTap: () => _save(widget.preference.defaultValue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
