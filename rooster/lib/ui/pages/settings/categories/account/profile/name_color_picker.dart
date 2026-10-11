import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// "Automatic" followed by a row of color swatches. [selected] is the index of
/// the chosen swatch in [colors], null for Automatic. [id] prefixes the keys of
/// the choices, so tests can tell two pickers on one page apart.
class ProfileColorPicker extends StatelessWidget {
  const ProfileColorPicker({
    super.key,
    required this.id,
    required this.colors,
    required this.selected,
    required this.onSelected,
    required this.automaticIcon,
  });

  final String id;
  final List<Color> colors;
  final int? selected;
  final ValueChanged<int?> onSelected;
  final Widget automaticIcon;

  static String get labelProfileSettingsAutomaticColor =>
      Intl.message("Automatic",
          name: "labelProfileSettingsAutomaticColor",
          desc: "Settings > Profile: the color choice that lets the color be "
              "worked out for you, before the swatches of a color picker");

  static String labelProfileSettingsColorSwatch(int number, int count) =>
      Intl.message("Color $number of $count",
          name: "labelProfileSettingsColorSwatch",
          args: [number, count],
          desc: "Settings > Profile: what a screen reader says for a color "
              "swatch in a color picker, such as 'Color 3 of 12'");

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          key: ValueKey("$id-automatic"),
          avatar: automaticIcon,
          showCheckmark: false,
          label: Text(labelProfileSettingsAutomaticColor),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final (i, color) in colors.indexed) swatch(context, i, color),
      ],
    );
  }

  Widget swatch(BuildContext context, int index, Color color) {
    final isSelected = index == selected;
    return Semantics(
      button: true,
      selected: isSelected,
      label: labelProfileSettingsColorSwatch(index + 1, colors.length),
      child: Material(
        color: color,
        clipBehavior: Clip.antiAlias,
        shape: CircleBorder(
          side: isSelected
              ? BorderSide(
                  color: Theme.of(context).colorScheme.onSurface, width: 3)
              : BorderSide.none,
        ),
        child: InkWell(
          key: ValueKey("$id-$index"),
          onTap: () => onSelected(index),
          child: SizedBox(
            width: 36,
            height: 36,
            child: isSelected
                ? Icon(Icons.check,
                    size: 20,
                    color: color.computeLuminance() > 0.4
                        ? Colors.black
                        : Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}
