import 'dart:math';

import 'package:web/web.dart' as web;

bool? _touch;

/// Read once: what a device is held and pointed at with does not change
/// under a page.
bool get primaryPointerIsTouch => _touch ??=
    web.window.matchMedia('(hover: none) and (pointer: coarse)').matches;

/// Read every time: folding and unfolding changes the screen in use.
double? get screenShortestSide {
  final screen = web.window.screen;
  final side = min(screen.width, screen.height).toDouble();
  return side > 0 ? side : null;
}
