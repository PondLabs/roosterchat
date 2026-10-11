import 'dart:async';

import 'package:rooster/client/components/voip/audio_processing/audio_processing_manager.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/speaking_indicator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Turns noise suppression on and off from the call panel, beside mute and
/// deafen, without opening the settings. Hovering it explains what it does,
/// in the settings' words. Not shown where the voice DSP cannot run.
class NoiseSuppressionButton extends StatefulWidget {
  const NoiseSuppressionButton({this.size = 20, this.extent = 40, super.key});

  /// The icon's size, and the square the button takes beside the others.
  final double size;
  final double extent;

  static String get labelVoipNoiseSuppression => Intl.message(
      "Noise suppression",
      name: "labelVoipNoiseSuppression",
      desc: "Label for the toggle that enables microphone noise suppression");

  static String get labelVoipNoiseSuppressionDescription => Intl.message(
      "Removes background noise, keyboard clicks and clapping from your microphone before it is sent to others. Runs on your device.",
      name: "labelVoipNoiseSuppressionDescription",
      desc: "Describes the microphone noise suppression toggle");

  static String get labelNoiseSuppressionButtonOn => Intl.message("On",
      name: "labelNoiseSuppressionButtonOn",
      desc:
          "In the tooltip of the call panel's noise suppression button, after its name: noise suppression is on");

  static String get labelNoiseSuppressionButtonOff => Intl.message("Off",
      name: "labelNoiseSuppressionButtonOff",
      desc:
          "In the tooltip of the call panel's noise suppression button, after its name: noise suppression is off");

  @override
  State<NoiseSuppressionButton> createState() => _NoiseSuppressionButtonState();
}

class _NoiseSuppressionButtonState extends State<NoiseSuppressionButton> {
  late final List<StreamSubscription> _subs;

  @override
  void initState() {
    super.initState();
    final manager = AudioProcessingManager.instance;
    _subs = [
      preferences.onSettingChanged.listen((_) {
        if (mounted) setState(() {});
      }),
      manager.onStateChanged.listen((_) {
        if (mounted) setState(() {});
      }),
    ];
    // On the web whether the DSP runs is only known once its wasm is tried.
    manager.ensureReady().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AudioProcessingManager.instance.isSupported) {
      return const SizedBox.shrink();
    }
    final on = preferences.voipNoiseSuppression.value;
    final theme = Theme.of(context);
    return Tooltip(
      // A small card, not a one-line tooltip: the name, whether it is on,
      // and what it does.
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(blurRadius: 12, color: Colors.black38, offset: Offset(0, 4))
        ],
      ),
      richMessage: TextSpan(children: [
        TextSpan(
          text: NoiseSuppressionButton.labelVoipNoiseSuppression,
          style: theme.textTheme.titleSmall,
        ),
        TextSpan(
          // Not translated: a separator between the name and its state.
          text: " · ",
          style: theme.textTheme.titleSmall,
        ),
        TextSpan(
          text: on
              ? NoiseSuppressionButton.labelNoiseSuppressionButtonOn
              : NoiseSuppressionButton.labelNoiseSuppressionButtonOff,
          style: theme.textTheme.titleSmall?.copyWith(
              color: on
                  ? SpeakingIndicator.color
                  : theme.colorScheme.onSurfaceVariant),
        ),
        TextSpan(
          text:
              "\n${NoiseSuppressionButton.labelVoipNoiseSuppressionDescription}",
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ]),
      child: SizedBox(
        width: widget.extent,
        height: widget.extent,
        child: tiamat.IconButton(
          onPressed: () => preferences.voipNoiseSuppression.set(!on),
          size: widget.size,
          iconColor: on ? SpeakingIndicator.color : null,
          icon:
              on ? Icons.noise_aware_rounded : Icons.noise_control_off_rounded,
        ),
      ),
    );
  }
}
