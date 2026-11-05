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

  group('the marker shows only for a nest out of sight', () {
    const screen = Size(1280, 800);
    const strip = Rect.fromLTRB(474, 0, 806, 98);
    const card = Rect.fromLTRB(0, 742, 260, 800);
    PuttNestPointer? markerFor(Offset nest, {bool behind = false}) =>
        puttNestMarkerFor(nest,
            behind: behind,
            view: screen,
            free: view,
            hud: const [strip, card],
            number: '4');

    test('a nest on screen, above or below the free part, has none', () {
      // Round 4 put markers beside nests in plain sight: in the top band
      // clear of the strip, and in the bottom one clear of the card.
      expect(markerFor(const Offset(300, 60)), isNull);
      expect(markerFor(const Offset(640, 720)), isNull);
      expect(markerFor(const Offset(640, 300)), isNull);
    });

    test('a nest under a HUD widget is pointed at', () {
      final marker = markerFor(const Offset(640, 40))!;
      expect(marker.angle, lessThan(0), reason: 'up, toward the strip');
      expect(markerFor(const Offset(120, 780)), isNotNull,
          reason: 'under the scorecard');
    });

    test('never on the rim of the nest it points at', () {
      // Just under the strip's lower edge: the marker would stand on it.
      expect(markerFor(const Offset(640, 96)), isNull);
    });

    test('off the screen, or behind the camera, it shows', () {
      expect(markerFor(const Offset(2400, 400)), isNotNull);
      expect(markerFor(const Offset(640, 300), behind: true), isNotNull);
    });
  });
}
