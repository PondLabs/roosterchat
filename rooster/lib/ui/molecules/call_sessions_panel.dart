import 'dart:async';

import 'package:rooster/client/components/voip/call_connection.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/anchored_popover.dart';
import 'package:rooster/ui/atoms/noise_suppression_button.dart';
import 'package:rooster/ui/atoms/speaking_indicator.dart';
import 'package:rooster/ui/molecules/call_connection_status.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/molecules/call_session_live_panel.dart';
import 'package:rooster/ui/molecules/screen_share_start_reporting.dart';
import 'package:rooster/ui/molecules/screen_share_stop_reporting.dart';
import 'package:rooster/ui/organisms/call_view/call_view.dart';
import 'package:rooster/ui/organisms/soundboard/soundboard_button.dart';
import 'package:rooster/ui/organisms/soundboard/soundboard_call_controller.dart';
import 'package:rooster/utils/animation/ring_shaker.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:rooster/utils/voice_controls/browser_call_controls.dart';
import 'package:rooster/utils/voice_controls/voice_controls.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class CallSessionsPanel extends StatefulWidget {
  const CallSessionsPanel({this.height = 50, super.key});
  final double height;
  @override
  State<CallSessionsPanel> createState() => _CallSessionsPanelState();
}

class _CallSessionsPanelState extends State<CallSessionsPanel> {
  StreamSubscription? sub;

  @override
  void initState() {
    sub = clientManager!.callManager.currentSessions.onListUpdated.listen((_) {
      setState(() {});
    });

    super.initState();
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: ColorScheme.of(context).surfaceTint.withAlpha(10),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          for (var entry in clientManager!.callManager.currentSessions)
            ClipRRect(
              borderRadius: BorderRadiusGeometry.circular(8),
              child: CallSessionPanel(
                session: entry,
                height: widget.height,
              ),
            ),
        ],
      ),
    );
  }
}

class CallSessionPanel extends StatefulWidget {
  const CallSessionPanel({required this.session, this.height = 40, super.key});
  final VoipSession session;
  final double height;
  @override
  State<CallSessionPanel> createState() => _CallSessionPanelState();
}

class _CallSessionPanelState extends State<CallSessionPanel>
    with TickerProviderStateMixin {
  /// The control buttons sit in boxes the height of the whole row, so
  /// tiamat's 15px default left them looking lost in all that space.
  static const double iconSize = 20;

  String get tooltipPopOutControls => Intl.message("Pop out call controls",
      name: "tooltipPopOutControls",
      desc: "Tooltip on the call panel button (browser only) that opens the "
          "mute, deafen and disconnect buttons in a small window that stays "
          "on top of other windows");

  late List<StreamSubscription> subs;
  Timer? statUpdateTimer;
  late AnimationController audioLevel;
  Room? room;
  late final SoundboardCallController soundboard;
  bool _screenShareBusy = false;

  String get tooltipShareScreen => Intl.message("Share your screen",
      name: "tooltipShareScreen",
      desc: "Tooltip on the voice panel button that starts screen sharing");

  String get tooltipStopSharingScreen => Intl.message("Stop sharing",
      name: "tooltipStopSharingScreen",
      desc: "Tooltip on the voice panel button that stops screen sharing");

  String get tooltipTurnOnCamera => Intl.message("Turn on camera",
      name: "tooltipTurnOnCamera",
      desc: "Tooltip on the voice panel button that turns our camera on");

  String get tooltipTurnOffCamera => Intl.message("Turn off camera",
      name: "tooltipTurnOffCamera",
      desc: "Tooltip on the voice panel button that turns our camera off");

  String get tooltipSelectingScreen => Intl.message("Selecting screen",
      name: "tooltipSelectingScreen",
      desc:
          "Tooltip on the voice panel button while the screen picker is open");

  @override
  void initState() {
    room = widget.session.client.getRoom(widget.session.roomId);
    soundboard = SoundboardCallController.acquire(widget.session);

    audioLevel = AnimationController(
        vsync: this, duration: CallView.volumeAnimationDuration);

    subs = [
      widget.session.onStateChanged.listen((event) {
        setState(() {});
      }),
      widget.session.onUpdateVolumeVisualizers.listen((_) async {
        await widget.session.updateStats();
        audioLevel.animateTo(localAudioLevel);
      })
    ];

    super.initState();
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    statUpdateTimer?.cancel();
    soundboard.release();
    super.dispose();
  }

  double get localAudioLevel => VoiceCallState.ownAudioLevel(widget.session);

  void openRoom() {
    EventBus.doOpenRoom(widget.session.roomId,
        clientId: widget.session.client.identifier);
  }

  bool _cameraBusy = false;

  Future<void> toggleCamera() async {
    if (_cameraBusy) return;
    setState(() => _cameraBusy = true);
    try {
      if (widget.session.isCameraEnabled) {
        await stopCameraOrReportFailure(context, widget.session);
      } else {
        await widget.session.setCamera(null);
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Could not turn the camera on or off");
      if (mounted) AdaptiveDialog.showError(context, e, s);
    } finally {
      if (mounted) setState(() => _cameraBusy = false);
    }
  }

  Future<void> toggleScreenShare() async {
    if (!mounted || _screenShareBusy) return;
    setState(() => _screenShareBusy = true);

    try {
      if (widget.session.isSharingScreen) {
        await stopScreenshareOrReportFailure(context, widget.session);
        return;
      }

      await startScreenshareOrReportFailure(context, widget.session);
    } finally {
      if (mounted) setState(() => _screenShareBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.session case final CallConnection connection)
            CallConnectionStatus(
                session: widget.session,
                connection: connection,
                onOpenRoom: openRoom),
          buildControlsRow(context),
          // Grows the panel below the button row while sharing screen /
          // camera; renders nothing otherwise.
          CallSessionLivePanel(session: widget.session, onOpenRoom: openRoom),
        ],
      ),
    );
  }

  Widget buildControlsRow(BuildContext context) {
    return InkWell(
        onTap: openRoom,
        child: SizedBox(
          height: widget.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    pickAnimation(
                        entry: widget.session,
                        child: SizedBox(
                          height: widget.height,
                          width: widget.height,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: buildActivityIndicator(context),
                          ),
                        )),
                    // The status row above names the room.
                    if (widget.session is! CallConnection)
                      Flexible(
                        child: tiamat.Text(widget.session.roomName,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: widget.height,
                    height: widget.height,
                    child: AspectRatio(
                        aspectRatio: 1.0,
                        child: tiamat.IconButton(
                            onPressed: () {
                              if (widget.session.isMicrophoneMuted) {
                                clientManager!.callManager.unmute();
                              } else {
                                clientManager!.callManager.mute();
                              }
                            },
                            size: iconSize,
                            iconColor: widget.session.isMicrophoneMuted
                                ? ColorScheme.of(context).error
                                : null,
                            icon: widget.session.isMicrophoneMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded)),
                  ),
                  SizedBox(
                    width: widget.height,
                    height: widget.height,
                    child: AspectRatio(
                        aspectRatio: 1.0,
                        child: tiamat.IconButton(
                            onPressed: () {
                              if (widget.session.isDeafened) {
                                clientManager!.callManager.undeafen();
                              } else {
                                clientManager!.callManager.deafen();
                              }
                            },
                            size: iconSize,
                            iconColor: widget.session.isDeafened
                                ? ColorScheme.of(context).error
                                : null,
                            icon: widget.session.isDeafened
                                ? Icons.headset_off_rounded
                                : Icons.headset_rounded)),
                  ),
                  // Hides itself where the voice DSP cannot run.
                  NoiseSuppressionButton(size: iconSize, extent: widget.height),
                  SizedBox(
                    width: widget.height,
                    height: widget.height,
                    child: Tooltip(
                      message: widget.session.isCameraEnabled
                          ? tooltipTurnOffCamera
                          : tooltipTurnOnCamera,
                      child: tiamat.IconButton(
                        onPressed: _cameraBusy ? null : toggleCamera,
                        size: iconSize,
                        iconColor: widget.session.isCameraEnabled
                            ? SpeakingIndicator.color
                            : null,
                        icon: widget.session.isCameraEnabled
                            ? Icons.videocam_rounded
                            : Icons.videocam_outlined,
                      ),
                    ),
                  ),
                  if (widget.session.supportsScreenshare)
                    SizedBox(
                      width: widget.height,
                      height: widget.height,
                      child: Tooltip(
                        message: _screenShareBusy
                            ? tooltipSelectingScreen
                            : widget.session.isSharingScreen
                                ? tooltipStopSharingScreen
                                : tooltipShareScreen,
                        child: tiamat.IconButton(
                          onPressed:
                              _screenShareBusy ? null : toggleScreenShare,
                          size: iconSize,
                          iconColor: widget.session.isSharingScreen
                              ? SpeakingIndicator.color
                              : null,
                          icon: widget.session.isSharingScreen
                              ? Icons.stop_screen_share_rounded
                              : Icons.screen_share_outlined,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: widget.height,
                    height: widget.height,
                    child: SoundboardButton(
                      controller: soundboard,
                      deafened: widget.session.isDeafened,
                      alignment: PopoverAlignment.start,
                      builder: (context, onPressed) => tiamat.IconButton(
                        onPressed: onPressed,
                        size: iconSize,
                        iconColor: onPressed == null
                            ? Theme.of(context).disabledColor
                            : null,
                        icon: Icons.surround_sound_rounded,
                      ),
                    ),
                  ),
                  // The call controls in a small window of their own that
                  // floats over other apps: the browser's stand-in for the
                  // taskbar buttons (issue #146).
                  if (BrowserCallControls.canPopOut)
                    SizedBox(
                      width: widget.height,
                      height: widget.height,
                      child: Tooltip(
                        message: tooltipPopOutControls,
                        child: tiamat.IconButton(
                            onPressed: BrowserCallControls.popOut,
                            size: iconSize,
                            icon: Icons.picture_in_picture_alt_rounded),
                      ),
                    ),
                  SizedBox(
                    width: widget.height,
                    height: widget.height,
                    child: AspectRatio(
                        aspectRatio: 1.0,
                        child: tiamat.IconButton(
                            onPressed: () {
                              widget.session.hangUpCall();
                            },
                            size: iconSize,
                            iconColor: ColorScheme.of(context).error,
                            icon: Icons.call_end_rounded)),
                  ),
                ],
              ),
            ],
          ),
        ));
  }

  /// Crossed out and red while we are not transmitting, and then static:
  /// lighting up for voice activity would suggest the microphone is live.
  Widget buildActivityIndicator(BuildContext context) {
    final silenced =
        widget.session.isMicrophoneMuted || widget.session.isDeafened;

    if (silenced) {
      return Icon(
        Icons.volume_off_rounded,
        color: ColorScheme.of(context).error,
        size: iconSize,
      );
    }

    return AnimatedBuilder(
      animation: audioLevel,
      builder: (context, child) {
        return Icon(
          Icons.volume_up_rounded,
          color: Color.lerp(
            ColorScheme.of(context).onSurface,
            SpeakingIndicator.color,
            audioLevel.value,
          ),
          size: iconSize,
        );
      },
    );
  }

  Widget pickAnimation({required VoipSession entry, required Widget child}) {
    if (entry.state == VoipState.incoming) {
      return RingShakerAnimation(child: child);
    }

    return child;
  }
}
