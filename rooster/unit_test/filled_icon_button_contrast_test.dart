// A filled icon button's icon has to stand out from its fill, in every theme
// the app has: the DJ booth's play button was all but invisible under the
// theme built from the Windows accent colour (filled_icon_button_style.dart).
import 'dart:math';

import 'package:rooster/ui/atoms/filled_icon_button_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_light.dart';
import 'package:tiamat/config/style/theme_you.dart';

/// WCAG contrast ratio, 1 (none) to 21.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

/// What WCAG asks of an icon against what surrounds it.
const minContrast = 3.0;

const accents = {
  'orange': Color(0xFFFF8C00),
  'blue': Color(0xFF0078D4),
  'green': Color(0xFF107C10),
  'purple': Color(0xFF8764B8),
  'red': Color(0xFFE81123),
  'yellow': Color(0xFFFFB900),
};

final themes = <String, ThemeData>{
  'dark': ThemeDark.theme,
  'light': ThemeLight.theme,
  'amoled': ThemeAmoled.theme,
  for (final MapEntry(key: name, value: accent) in accents.entries) ...{
    'system dark, $name accent':
        ThemeYou.withSeedColor(Brightness.dark, accent),
    'system light, $name accent':
        ThemeYou.withSeedColor(Brightness.light, accent),
  },
};

/// The fill and icon colour [button] comes out with in [theme].
Future<(Color fill, Color icon)> render(WidgetTester tester, ThemeData theme,
    Widget Function(BuildContext) button) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(body: Center(child: Builder(builder: button))),
  ));
  final icon = find.byIcon(Icons.play_arrow_rounded);
  final fill = tester
      .widgetList<Material>(
          find.ancestor(of: icon, matching: find.byType(Material)))
      .first
      .color!;
  return (fill, IconTheme.of(tester.element(icon)).color!);
}

void main() {
  const play = Icon(Icons.play_arrow_rounded);

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    testWidgets('filled: the icon stands out, $name theme', (tester) async {
      final (fill, icon) = await render(
          tester,
          theme,
          (context) => IconButton.filled(
              style: filledIconButtonStyle(context),
              onPressed: () {},
              icon: play));
      expect(contrast(fill, icon), greaterThanOrEqualTo(minContrast),
          reason: 'icon $icon on $fill');
    });

    testWidgets('filled tonal: the icon stands out, $name theme',
        (tester) async {
      final (fill, icon) = await render(
          tester,
          theme,
          (context) => IconButton.filledTonal(
              style: filledTonalIconButtonStyle(context),
              onPressed: () {},
              icon: play));
      expect(contrast(fill, icon), greaterThanOrEqualTo(minContrast),
          reason: 'icon $icon on $fill');
    });
  }

  testWidgets('without the style the icon is lost (why the style is there)',
      (tester) async {
    final (fill, icon) = await render(
        tester,
        themes['system dark, orange accent']!,
        (_) => IconButton.filled(onPressed: () {}, icon: play));
    expect(contrast(fill, icon), lessThan(minContrast));
  });
}
