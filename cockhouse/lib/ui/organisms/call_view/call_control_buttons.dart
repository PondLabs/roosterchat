import 'dart:async';

import 'package:cockhouse/client/components/voip/voip_session.dart';
import 'package:cockhouse/ui/organisms/soundboard/soundboard_button.dart';
import 'package:cockhouse/ui/organisms/soundboard/soundboard_call_controller.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What the call's buttons do. Handed from the call view to the fullscreen
/// stream view, so the same buttons work over a fullscreen stream.
class CallControlActions {
  const CallControlActions({
    this.setMicrophoneMute,
    this.setDeafened,
    this.pickScreenshareSource,
    this.stopScreenshare,
    this.pickCamera,
    this.disableCamera,
    this.hangUp,
    this.soundboard,
  });

  final Future<void> Function(bool)? setMicrophoneMute;
  final Future<void> Function(bool)? setDeafened;
  final Future<void> Function()? pickScreenshareSource;
  final Future<void> Function()? stopScreenshare;
  final Future<void> Function()? pickCamera;
  final Future<void> Function()? disableCamera;
  final Future<void> Function()? hangUp;
  final SoundboardCallController? soundboard;
}

/// The row of buttons of a connected call: screen share, mute, deafen,
/// camera, soundboard, DJ booth and hang up.
class CallControlButtons extends StatefulWidget {
  const CallControlButtons({
    required this.session,
    required this.actions,
    required this.radius,
    this.spacing = 12,
    this.boothOpen = false,
    this.onToggleBooth,
    this.onHungUp,
    this.onSoundboardOpenChanged,
    super.key,
  });

  final VoipSession session;
  final CallControlActions actions;
  final double radius;
  final double spacing;

  final bool boothOpen;

  /// Null hides the DJ booth button.
  final VoidCallback? onToggleBooth;

  final VoidCallback? onHungUp;
  final ValueChanged<bool>? onSoundboardOpenChanged;

  @override
  State<CallControlButtons> createState() => _CallControlButtonsState();
}

class _CallControlButtonsState extends State<CallControlButtons> {
  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    sub = widget.session.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(CallControlButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      sub?.cancel();
      sub = widget.session.onStateChanged.listen((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final actions = widget.actions;
    final radius = widget.radius;
    final iconSize = radius * 1.2;
    final soundboard = actions.soundboard;
    final colors = Theme.of(context).colorScheme;

    return Wrap(
      spacing: widget.spacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        tiamat.CircleButton(
            radius: radius,
            iconSize: iconSize,
            icon: Icons.screen_share_outlined,
            onPressed: actions.pickScreenshareSource),
        if (session.isSharingScreen)
          tiamat.CircleButton(
            radius: radius,
            iconSize: iconSize,
            icon: Icons.stop_screen_share,
            onPressed: actions.stopScreenshare,
          ),
        tiamat.CircleButton(
          radius: radius,
          iconSize: iconSize,
          icon: session.isMicrophoneMuted ? Icons.mic_off : Icons.mic,
          color: session.isMicrophoneMuted ? colors.errorContainer : null,
          onPressed: () async {
            await actions.setMicrophoneMute?.call(!session.isMicrophoneMuted);
            if (mounted) setState(() {});
          },
        ),
        tiamat.CircleButton(
          radius: radius,
          iconSize: iconSize,
          icon: session.isDeafened ? Icons.headset_off : Icons.headset,
          color: session.isDeafened ? colors.errorContainer : null,
          onPressed: () async {
            await actions.setDeafened?.call(!session.isDeafened);
            if (mounted) setState(() {});
          },
        ),
        tiamat.CircleButton(
          radius: radius,
          iconSize: iconSize,
          icon: session.isCameraEnabled
              ? Icons.no_photography
              : Icons.camera_alt_outlined,
          onPressed: session.isCameraEnabled
              ? actions.disableCamera
              : actions.pickCamera,
        ),
        if (soundboard != null)
          SoundboardButton(
            controller: soundboard,
            deafened: session.isDeafened,
            onOpenChanged: widget.onSoundboardOpenChanged,
            builder: (context, onPressed) => tiamat.CircleButton(
              radius: radius,
              iconSize: iconSize,
              icon: Icons.surround_sound,
              iconColor:
                  onPressed == null ? Theme.of(context).disabledColor : null,
              onPressed: onPressed,
            ),
          ),
        if (widget.onToggleBooth != null)
          Tooltip(
            message: widget.boothOpen
                ? 'Close the DJ booth'
                : 'DJ booth – play music',
            child: tiamat.CircleButton(
              radius: radius,
              iconSize: iconSize,
              icon: Icons.album_rounded,
              color: widget.boothOpen ? colors.primaryContainer : null,
              onPressed: widget.onToggleBooth,
            ),
          ),
        tiamat.CircleButton(
          color: colors.errorContainer,
          radius: radius,
          iconSize: iconSize,
          icon: Icons.call_end,
          onPressed: () async {
            await actions.hangUp?.call();
            if (mounted) setState(() {});
            widget.onHungUp?.call();
          },
        )
      ],
    );
  }
}
