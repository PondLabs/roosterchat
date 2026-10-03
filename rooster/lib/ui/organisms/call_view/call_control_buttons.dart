import 'dart:async';
import 'dart:math';

import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/ui/molecules/screen_share_start_reporting.dart';
import 'package:rooster/ui/organisms/soundboard/soundboard_button.dart';
import 'package:rooster/ui/organisms/soundboard/soundboard_call_controller.dart';
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
    this.compact = false,
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

  /// One evenly spaced row for a phone: mic, deafen, camera, soundboard, a
  /// "more" sheet (screen share, DJ booth) and hang up. The full set of
  /// buttons wrapped onto a second, left-aligned row on every common phone.
  final bool compact;

  final bool boothOpen;

  /// Null hides the DJ booth button.
  final VoidCallback? onToggleBooth;

  final VoidCallback? onHungUp;
  final ValueChanged<bool>? onSoundboardOpenChanged;

  /// The least room left between two buttons of the compact row.
  static const double _compactGap = 4;

  /// The radius the compact row's [count] buttons get in [width]: the one
  /// asked for where they fit, smaller where they do not. A foldable's
  /// cover screen (280 logical pixels on the early ones) is narrower than
  /// six touch-sized buttons, and the row ran off its edge.
  static double compactRadius(
      {required double asked, required double width, required int count}) {
    if (!width.isFinite) return asked;
    final fits = (width / count - _compactGap) / 2;
    return min(asked, max(fits, 12));
  }

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
    if (!widget.compact) return _buildButtons(context, widget.radius);
    return LayoutBuilder(
      builder: (context, constraints) => _buildButtons(
          context,
          CallControlButtons.compactRadius(
              asked: widget.radius,
              width: constraints.maxWidth,
              // Mic, deafen, camera, more and hang up, and the soundboard.
              count: widget.actions.soundboard == null ? 5 : 6)),
    );
  }

  Widget _buildButtons(BuildContext context, double radius) {
    final session = widget.session;
    final actions = widget.actions;
    final iconSize = radius * 1.2;
    final soundboard = actions.soundboard;
    final colors = Theme.of(context).colorScheme;

    // Where the screen cannot be captured (a phone's browser, also on an
    // unfolded foldable, which gets this full row) the button stays, greyed
    // out, and says why when pressed: it used to look ready and do nothing.
    final shareScreen = tiamat.CircleButton(
        radius: radius,
        iconSize: iconSize,
        icon: Icons.screen_share_outlined,
        iconColor: session.supportsScreenshare
            ? null
            : Theme.of(context).disabledColor,
        onPressed: actions.pickScreenshareSource);
    final stopSharing = tiamat.CircleButton(
      radius: radius,
      iconSize: iconSize,
      icon: Icons.stop_screen_share,
      onPressed: actions.stopScreenshare,
    );
    final mic = tiamat.CircleButton(
      radius: radius,
      iconSize: iconSize,
      icon: session.isMicrophoneMuted ? Icons.mic_off : Icons.mic,
      color: session.isMicrophoneMuted ? colors.errorContainer : null,
      onPressed: () async {
        await actions.setMicrophoneMute?.call(!session.isMicrophoneMuted);
        if (mounted) setState(() {});
      },
    );
    final deafen = tiamat.CircleButton(
      radius: radius,
      iconSize: iconSize,
      icon: session.isDeafened ? Icons.headset_off : Icons.headset,
      color: session.isDeafened ? colors.errorContainer : null,
      onPressed: () async {
        await actions.setDeafened?.call(!session.isDeafened);
        if (mounted) setState(() {});
      },
    );
    final camera = tiamat.CircleButton(
      radius: radius,
      iconSize: iconSize,
      icon: session.isCameraEnabled
          ? Icons.no_photography
          : Icons.camera_alt_outlined,
      onPressed:
          session.isCameraEnabled ? actions.disableCamera : actions.pickCamera,
    );
    final soundboardButton = soundboard == null
        ? null
        : SoundboardButton(
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
          );
    final booth = widget.onToggleBooth == null
        ? null
        : Tooltip(
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
          );
    final hangUp = tiamat.CircleButton(
      color: colors.errorContainer,
      radius: radius,
      iconSize: iconSize,
      icon: Icons.call_end,
      onPressed: () async {
        await actions.hangUp?.call();
        if (mounted) setState(() {});
        widget.onHungUp?.call();
      },
    );

    if (widget.compact) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          mic,
          deafen,
          camera,
          if (soundboardButton != null) soundboardButton,
          tiamat.CircleButton(
            radius: radius,
            iconSize: iconSize,
            icon: Icons.more_horiz,
            color: session.isSharingScreen || widget.boothOpen
                ? colors.primaryContainer
                : null,
            onPressed: () => _showMore(context),
          ),
          hangUp,
        ],
      );
    }

    return Wrap(
      spacing: widget.spacing,
      runSpacing: widget.spacing,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        shareScreen,
        if (session.isSharingScreen) stopSharing,
        mic,
        deafen,
        camera,
        if (soundboardButton != null) soundboardButton,
        if (booth != null) booth,
        hangUp,
      ],
    );
  }

  /// The compact row's "more": what a phone uses less.
  Future<void> _showMore(BuildContext context) {
    final session = widget.session;
    final actions = widget.actions;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (session.isSharingScreen)
              ListTile(
                leading: const Icon(Icons.stop_screen_share),
                title: const Text('Stop sharing your screen'),
                onTap: () {
                  Navigator.pop(sheet);
                  actions.stopScreenshare?.call();
                },
              )
            else if (actions.pickScreenshareSource != null)
              ListTile(
                key: const ValueKey('callControls_shareScreen'),
                leading: const Icon(Icons.screen_share_outlined),
                title: const Text('Share your screen'),
                // A phone's browser cannot capture the screen: said here,
                // rather than a tile that does nothing when tapped.
                enabled: session.supportsScreenshare,
                subtitle: session.supportsScreenshare
                    ? null
                    : Text(messageScreenShareUnsupported),
                onTap: () {
                  Navigator.pop(sheet);
                  actions.pickScreenshareSource?.call();
                },
              ),
            if (widget.onToggleBooth != null)
              ListTile(
                leading: const Icon(Icons.album_rounded),
                title: Text(widget.boothOpen
                    ? 'Close the DJ booth'
                    : 'DJ booth – play music'),
                onTap: () {
                  Navigator.pop(sheet);
                  widget.onToggleBooth?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}
