// Icon colours for IconButton.filled and IconButton.filledTonal.
//
// The theme gives every icon the secondary colour (tiamat's ThemeBase sets
// Theme.iconTheme), and in Material 3 an IconButton takes the ambient icon
// colour over its variant's own whenever that colour is not Flutter's
// default. A filled button then draws a secondary icon on a primary fill,
// two light colours in a dark theme: the DJ booth's play button was all but
// invisible under the theme built from the Windows accent colour. A style on
// the button itself comes before that, so these put the variant's colours
// back.
import 'package:flutter/material.dart';

/// For IconButton.filled: the icon on the primary fill.
ButtonStyle filledIconButtonStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return IconButton.styleFrom(
    foregroundColor: scheme.onPrimary,
    disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
  );
}

/// For IconButton.filledTonal: the icon on the secondary container.
ButtonStyle filledTonalIconButtonStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return IconButton.styleFrom(
    foregroundColor: scheme.onSecondaryContainer,
    disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
  );
}
