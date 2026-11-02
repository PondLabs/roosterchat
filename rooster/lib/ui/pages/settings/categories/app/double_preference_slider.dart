import 'package:rooster/config/preferences/double_preference.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import 'package:tiamat/tiamat.dart' as tiamat;

class DoublePreferenceSlider extends StatefulWidget {
  const DoublePreferenceSlider(
      {required this.preference,
      required this.min,
      required this.max,
      required this.title,
      this.units,
      this.description,
      this.numDecimals = 1,
      this.requiresConfirmationButton = false,
      this.onChanged,
      super.key});

  final DoublePreference preference;
  final Function(double)? onChanged;
  final String? units;

  final double min;
  final double max;
  final bool requiresConfirmationButton;
  final int numDecimals;
  final String title;
  final String? description;

  @override
  State<DoublePreferenceSlider> createState() => _DoublePreferenceSliderState();
}

class _DoublePreferenceSliderState extends State<DoublePreferenceSlider> {
  late double value;

  @override
  void initState() {
    value = widget.preference.value;
    super.initState();
  }

  /// The value with the language's decimal separator ("1,5" in Portuguese).
  String get formattedValue => NumberFormat(
          widget.numDecimals > 0 ? "0.${"0" * widget.numDecimals}" : "0")
      .format(value);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: ColorScheme.of(context).surfaceContainer.withAlpha(100),
          border: BoxBorder.all(
              color: ColorScheme.of(context).secondary.withAlpha(20)),
          borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.Text(widget.title),
            if (widget.description != null)
              tiamat.Text.labelLow(widget.description!),
            Row(
              children: [
                tiamat.Text.labelLow("$formattedValue${widget.units ?? ""}"),
                Expanded(
                  child: tiamat.Slider(
                    value: value,
                    min: widget.min,
                    max: widget.max,
                    onChanged: (newValue) {
                      var strValue =
                          newValue.toStringAsFixed(widget.numDecimals);
                      var finalValue = double.parse(strValue);
                      setState(() {
                        value = finalValue;

                        if (!widget.requiresConfirmationButton) {
                          widget.onChanged?.call(finalValue);
                          widget.preference.set(finalValue);
                        }
                      });
                    },
                  ),
                ),
                if (widget.requiresConfirmationButton)
                  tiamat.Button.secondary(
                    text: CommonStrings.promptApply,
                    onTap: () {
                      widget.preference.set(value);
                      widget.onChanged?.call(value);
                    },
                  )
              ],
            )
          ],
        ),
      ),
    );
  }
}
