// The off-screen nest's marker: none while the nest shows in the part of
// the screen the HUD leaves free; otherwise on that part's edge, pointing
// at the nest - the other way when the nest is behind the camera.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_nest_marker.dart';

void main() {
  const view = Rect.fromLTRB(16, 104, 1264, 640);
  final inner = view.deflate(puttNestMarkerRadius + 6);

  test('a nest on screen needs no marker', () {
    expect(
        puttNestPointer(const Offset(640, 300), view,
            behind: false, number: '3'),
        isNull);
  });

  test('a nest off to the right is pointed at from the right edge', () {
    final marker = puttNestPointer(Offset(2400, view.center.dy), view,
        behind: false, number: '3')!;
    expect(marker.at.dx, closeTo(inner.right, 1e-6));
    expect(marker.at.dy, closeTo(view.center.dy, 1e-6));
    expect(marker.angle, closeTo(0, 1e-9));
    expect(marker.number, '3');
  });

  test('a nest under the top bar is pointed at from the top edge', () {
    final marker = puttNestPointer(const Offset(700, 40), view,
        behind: false, number: '5')!;
    expect(marker.at.dy, closeTo(inner.top, 1e-6));
    expect(view.contains(marker.at), isTrue);
    expect(marker.angle, lessThan(0), reason: 'up the screen');
  });

  test('a nest behind the camera is pointed at the other way', () {
    // Projected through the camera, it lands above the middle: it is
    // really behind, so the marker points down.
    final marker = puttNestPointer(Offset(view.center.dx, 200), view,
        behind: true, number: '1')!;
    expect(marker.at.dy, closeTo(inner.bottom, 1e-6));
    expect(marker.angle, closeTo(math.pi / 2, 1e-9));
  });
}
