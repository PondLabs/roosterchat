// Where the nest is when the camera is in close on my egg and the nest is
// off the screen (or behind it): a marker on the edge of the part of the
// screen the HUD leaves free, pointing at it - the flag with the hole's
// number, as the flag on the green flies it. The game hands the layer the
// marker's place after every rendered frame, like the name tags.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'putt_art.dart';

/// The marker this frame: where it stands, which way the nest lies from
/// it (radians, screen space: 0 is right, pi/2 down) and the flag's number.
@immutable
class PuttNestPointer {
  final Offset at;
  final double angle;
  final String number;

  const PuttNestPointer(
      {required this.at, required this.angle, required this.number});
}

/// The marker's radius, and how far inside the free view's edge its centre
/// stands.
const double puttNestMarkerRadius = 22;

/// The marker for a nest that projects to [target] (screen pixels), or
/// null when it shows inside [view] (the part of the screen the HUD leaves
/// free). A nest [behind] the camera projects through it: the marker then
/// points the other way.
PuttNestPointer? puttNestPointer(Offset target, Rect view,
    {required bool behind, required String number}) {
  if (!behind && view.contains(target)) return null;
  final centre = view.center;
  var way = target - centre;
  if (behind) way = -way;
  if (way.distance < 1e-6) way = const Offset(0, 1);
  final inner = view.deflate(puttNestMarkerRadius + 6);
  // The ray from the centre toward the nest, to where it leaves [inner].
  final sx = way.dx.abs() < 1e-9
      ? double.infinity
      : (way.dx > 0 ? inner.right - centre.dx : centre.dx - inner.left) /
          way.dx.abs();
  final sy = way.dy.abs() < 1e-9
      ? double.infinity
      : (way.dy > 0 ? inner.bottom - centre.dy : centre.dy - inner.top) /
          way.dy.abs();
  final s = math.max(0.0, math.min(sx, sy));
  return PuttNestPointer(
    at: centre + way * s,
    angle: math.atan2(way.dy, way.dx),
    number: number,
  );
}

/// The marker for this frame, or null: none while the nest projects
/// ([nest], screen pixels) onto the screen ([view]) clear of the [hud]'s
/// widgets, and none that would stand beside the nest itself. [free] is
/// the part of the screen the marker keeps to.
PuttNestPointer? puttNestMarkerFor(Offset nest,
    {required bool behind,
    required Size view,
    required Rect free,
    required List<Rect> hud,
    required String number}) {
  if (!behind &&
      (Offset.zero & view).deflate(8).contains(nest) &&
      !hud.any((rect) => rect.contains(nest))) {
    return null;
  }
  final pointer = puttNestPointer(nest, free, behind: behind, number: number);
  if (pointer == null) return null;
  // Under the HUD's edge, the marker would stand on the nest's rim.
  if (!behind && (pointer.at - nest).distance < puttNestMarkerRadius * 2.5) {
    return null;
  }
  return pointer;
}

/// The marker layer.
class PuttNestMarker extends StatelessWidget {
  final ValueListenable<PuttNestPointer?> pointer;

  const PuttNestMarker({super.key, required this.pointer});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ValueListenableBuilder<PuttNestPointer?>(
          valueListenable: pointer,
          builder: (context, marker, _) {
            if (marker == null) return const SizedBox.shrink();
            const size = puttNestMarkerRadius * 2 + 16;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: marker.at.dx - size / 2,
                  top: marker.at.dy - size / 2,
                  width: size,
                  height: size,
                  child: CustomPaint(
                    painter: _MarkerPainter(marker.angle),
                    child: Center(child: _Flag(number: marker.number)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The flag as the green flies it: a red pennant with the hole's number.
class _Flag extends StatelessWidget {
  final String number;

  const _Flag({required this.number});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.flag_rounded, size: 20, color: PuttPalette.comb),
        Text(
          number,
          style: const TextStyle(
            color: PuttPalette.cream,
            fontFamily: 'NunitoSans',
            fontSize: 14,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// The disc (ink, a yolk rim) and the pointer on its rim toward the nest.
class _MarkerPainter extends CustomPainter {
  final double angle;

  const _MarkerPainter(this.angle);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    const r = puttNestMarkerRadius;
    final along = Offset(math.cos(angle), math.sin(angle));
    final across = Offset(-along.dy, along.dx);
    final tip = centre + along * (r + 10);
    final pointer = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((centre + along * (r - 2) + across * 8).dx,
          (centre + along * (r - 2) + across * 8).dy)
      ..lineTo((centre + along * (r - 2) - across * 8).dx,
          (centre + along * (r - 2) - across * 8).dy)
      ..close();
    canvas
      ..drawCircle(centre + const Offset(0, 2), r,
          Paint()..color = const Color(0x55211614))
      ..drawPath(pointer, Paint()..color = PuttPalette.yolk)
      ..drawCircle(
          centre, r, Paint()..color = PuttPalette.ink.withValues(alpha: 0.92))
      ..drawCircle(
          centre,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = PuttPalette.yolk);
  }

  @override
  bool shouldRepaint(_MarkerPainter oldDelegate) => oldDelegate.angle != angle;
}
