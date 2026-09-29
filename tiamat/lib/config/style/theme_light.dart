import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_common.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:flutter/material.dart';

// The Cockhouse palette by day: eggshell and plaster surfaces, a deeper
// comb-red primary, hearth-brown text. See docs/brand/README.md.
class ThemeLightColors {
  static const Color surfaceHigh1 = Color(0xFFF6EFE5);
  static const Color primary = Color(0xFFC9452B);
  static const Color surface = Color(0xFFFBF6EF);
  static const Color surfaceContainer = Color(0xFFF0E7DA);
  static const Color surfaceContainerLow = Color(0xFFF6EFE5);
  static const Color surfaceContainerLowest = Color(0xFFFFFCF7);
  static const Color surfaceContainerHigh = Color(0xFFE9DECF);
  static const Color surfaceContainerHighest = Color(0xFFE2D5C3);

  static const Color secondary = Color(0xFF6F625A);
  static const Color surfaceLow1 = Color(0xFFF6EFE5);
  static const Color surfaceLow2 = Color(0xFFF0E7DA);
  static const Color surfaceLow3 = Color(0xFFE9DECF);
  static const Color surfaceLow4 = Color(0xFFE2D5C3);
  static const Color highlightColor = Colors.white30;
  static const Color onSurface = Color(0xFF231A16);
  static const Color outlineColor = Color(0x305C4A40);
}

class ThemeLight {
  static ThemeData get theme {
    var scheme = ColorScheme.fromSeed(
        dynamicSchemeVariant: DynamicSchemeVariant.neutral,
        seedColor: ThemeLightColors.primary,
        brightness: Brightness.light,
        surface: ThemeLightColors.surface,
        onSurface: ThemeLightColors.onSurface,
        surfaceDim: const Color(0xFFE4D7C6),
        surfaceContainer: ThemeLightColors.surfaceContainer,
        surfaceContainerLow: ThemeLightColors.surfaceContainerLow,
        surfaceContainerLowest: ThemeLightColors.surfaceContainerLowest,
        surfaceContainerHigh: ThemeLightColors.surfaceContainerHigh,
        surfaceContainerHighest: ThemeLightColors.surfaceContainerHighest,
        onSurfaceVariant: const Color(0xFF5C4F47),
        secondary: ThemeLightColors.secondary,
        primaryContainer: ThemeLightColors.primary,
        onPrimaryContainer: Colors.white,
        outline: Colors.white,
        tertiary: const Color(0xFFB8741C),
        tertiaryContainer: const Color(0x1FF2A33A),
        primary: ThemeLightColors.primary,
        // As in the dark theme. The seed's own is a light tone, hard to
        // read on the primary fill (a filled button's label, icon).
        onPrimary: Colors.white);

    return ThemeBase.theme(scheme).copyWith(extensions: [
      const ThemeSettings(),
      FoundationSettings(color: scheme.surfaceDim),
      const ExtraColors(
          codeHighlight: Color(0xFFA85B12), linkColor: Color(0xFF3D6B98))
    ]);
  }
}
