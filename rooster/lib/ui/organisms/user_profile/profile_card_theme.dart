import 'package:rooster/debug/log.dart';
import 'package:flutter/material.dart';

/// The colors of someone's profile card. The card and the preview in
/// Settings > Profile both use this, so the preview shows what others see.
///
/// A color the person picked wins. Without one, the colors come from their
/// banner, or their picture, or [fallbackColor]. [brightness] forces the card
/// light or dark for everyone; without it the card follows each viewer's
/// theme ([viewerBrightness]).
Future<ColorScheme> profileCardColorScheme({
  required Brightness viewerBrightness,
  required Color fallbackColor,
  Color? color,
  Brightness? brightness,
  ImageProvider? banner,
  ImageProvider? avatar,
}) async {
  final cardBrightness = brightness ?? viewerBrightness;

  if (color != null) {
    return ColorScheme.fromSeed(
        seedColor: color,
        brightness: cardBrightness,
        dynamicSchemeVariant: DynamicSchemeVariant.content);
  }

  final image = banner ?? avatar;
  if (image != null) {
    try {
      return await ColorScheme.fromImageProvider(
          provider: image,
          brightness: cardBrightness,
          dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not take profile colors from image");
    }
  }

  return ColorScheme.fromSeed(
      seedColor: fallbackColor,
      brightness: cardBrightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot);
}
