// How loud one person's soundboard sounds are for us, from their tile's menu:
// apart from their voice volume and from the DJ's music, so turning either
// of those down leaves their sounds alone, and the other way round.
import 'package:flutter/material.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/organisms/soundboard/soundboard_call_controller.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SoundboardUserVolumeSlider extends StatefulWidget {
  const SoundboardUserVolumeSlider(this.userId, {super.key});

  final String userId;

  @override
  State<SoundboardUserVolumeSlider> createState() =>
      _SoundboardUserVolumeSliderState();
}

class _SoundboardUserVolumeSliderState
    extends State<SoundboardUserVolumeSlider> {
  late double _volume = preferences.getSoundboardUserVolume(widget.userId);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        tiamat.Text.labelLow("${(_volume * 100).round()}%"),
        Expanded(
          child: tiamat.Slider(
            min: 0.0,
            max: 1.0,
            value: _volume.clamp(0.0, 1.0),
            onChanged: (value) {
              setState(() => _volume = value);
              preferences
                  .setSoundboardUserVolume(widget.userId, value)
                  .then((_) => SoundboardCallController.applySenderVolumes());
            },
          ),
        ),
      ],
    );
  }
}
