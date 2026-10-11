// The name colors Settings > Profile offers (name_color_palette.dart) have to
// be readable where names are drawn, in both themes, and tell people apart.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/ui/pages/settings/categories/account/profile/name_color_palette.dart';

/// WCAG contrast ratio, 1 (none) to 21.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

/// How far apart two hues are around the wheel, 0 to 180.
double hueDistance(Color a, Color b) {
  final d = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs();
  return min(d, 360 - d);
}

// The chat (surface) and member list (surfaceContainer) of each theme.
const darkBackgrounds = [Color(0xFF2A221E), Color(0xFF241D1A)];
const lightBackgrounds = [Color(0xFFFBF6EF), Color(0xFFF0E7DA)];

void main() {
  test('dark theme colors are light enough to be left as they are', () {
    for (final color in namePalette) {
      // tiamat's Text.adjustColor clamps names on dark themes to 0.75.
      expect(HSLColor.fromColor(color.onDark).lightness,
          greaterThanOrEqualTo(0.75),
          reason: '$color');
      for (final background in darkBackgrounds) {
        expect(contrast(color.onDark, background), greaterThanOrEqualTo(4.5),
            reason: '$color on $background');
      }
    }
  });

  test('light theme colors are dark enough to read', () {
    for (final color in namePalette) {
      // ...and to at most 0.7 on light ones.
      expect(
          HSLColor.fromColor(color.onLight).lightness, lessThanOrEqualTo(0.7),
          reason: '$color');
      for (final background in lightBackgrounds) {
        expect(contrast(color.onLight, background), greaterThanOrEqualTo(4.5),
            reason: '$color on $background');
      }
    }
  });

  test('every color is its own hue, the same in both themes', () {
    expect(namePalette.length, greaterThanOrEqualTo(10));
    for (final (i, a) in namePalette.indexed) {
      expect(hueDistance(a.onDark, a.onLight), lessThan(10), reason: '$a');
      for (final b in namePalette.skip(i + 1)) {
        expect(hueDistance(a.onDark, b.onDark), greaterThanOrEqualTo(15),
            reason: '$a and $b');
        expect(hueDistance(a.onLight, b.onLight), greaterThanOrEqualTo(15),
            reason: '$a and $b');
      }
    }
  });
}
