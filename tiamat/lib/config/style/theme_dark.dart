import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_common.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'dart:io' show Platform;

// The Rooster palette at night: warm dark-brown surfaces, comb-red
// primary, cream text. See docs/brand/README.md.
class ThemeDarkColors {
  static const Color surfaceContainerHigh = Color(0xFF362C27);
  static const Color secondary = Color(0xFF9C8F85);
  static const Color primary = Color(0xFFE8382A);
  static const Color surface = Color(0xFF2A221E);
  static const Color surfaceContainer = Color(0xFF241D1A);
  static const Color surfaceContainerLow = Color(0xFF1F1916);
  static const Color surfaceLow3 = Color(0xFF1B1613);
  static const Color surfaceContainerLowest = Color(0xFF161210);
  static const Color onSurface = Color(0xFFF5EBDD);
  static const Color highlightColor = Colors.white10;
  static const Color outlineColor = Color(0xFF1F1916);
}

class ThemeDark {
  static ThemeData get theme {
    var scheme = ColorScheme.fromSeed(
        seedColor: ThemeDarkColors.primary,
        dynamicSchemeVariant: DynamicSchemeVariant.neutral,
        primary: ThemeDarkColors.primary,
        onPrimary: const Color(0xFFFFF7EE),
        surface: ThemeDarkColors.surface,
        onSurface: ThemeDarkColors.onSurface,
        surfaceDim: ThemeDarkColors.surfaceLow3,
        surfaceContainer: ThemeDarkColors.surfaceContainer,
        surfaceContainerLow: ThemeDarkColors.surfaceContainerLow,
        surfaceContainerLowest: ThemeDarkColors.surfaceContainerLowest,
        surfaceContainerHigh: ThemeDarkColors.surfaceContainerHigh,
        surfaceContainerHighest: const Color(0xFF3F342E),
        onSurfaceVariant: const Color(0xFFC9BBAE),
        secondary: ThemeDarkColors.secondary,
        primaryContainer: ThemeDarkColors.primary,
        onPrimaryContainer: const Color(0xFFFFF7EE),
        tertiary: const Color(0xFFF2A33A),
        tertiaryContainer: const Color(0x14F2A33A),
        error: const Color(0xFFFF7B6B),
        brightness: Brightness.dark,
        outline: ThemeDarkColors.surfaceContainerHigh);

    return ThemeBase.theme(scheme).copyWith(extensions: [
      const ThemeSettings(caulkBorders: true, caulkBorderRadius: 1),
      FoundationSettings(color: scheme.surfaceDim),
      const ExtraColors(
          codeHighlight: Color(0xFFF2A33A), linkColor: Color(0xFF8FB4DA))
    ]);
  }
}
