import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Radio options whose labels wrap onto more lines instead of overflowing
/// (these labels are long, and longer still once translated).
class WrappingRadioOptions<T> extends StatelessWidget {
  const WrappingRadioOptions({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.options,
  });

  final T value;
  final bool enabled;
  final void Function(T? value) onChanged;
  final List<(T, IconData, String)> options;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;
    return RadioGroup<T>(
      groupValue: value,
      onChanged: (next) {
        if (enabled) onChanged(next);
      },
      child: Column(
        children: [
          for (final (option, icon, text) in options)
            RadioListTile<T>(
              value: option,
              enabled: enabled,
              tileColor: Colors.transparent,
              controlAffinity: ListTileControlAffinity.trailing,
              title: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(icon,
                        color: option == value ? selectedColor : null),
                  ),
                  Expanded(
                    child: tiamat.Text.labelEmphasised(text,
                        color: option == value ? selectedColor : null),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
