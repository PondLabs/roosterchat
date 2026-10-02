import 'dart:async';
import 'package:rooster/client/components/dj/dj_session.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/dj/dj_booths.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/ui/layout/bento.dart';
import 'package:rooster/ui/organisms/call_view/call_control_buttons.dart';
import 'package:rooster/ui/organisms/call_view/call_grid_tiles.dart';
import 'package:rooster/ui/organisms/call_view/voip_fullscreen_stream_view.dart';
import 'package:rooster/ui/organisms/call_view/voip_stream_view.dart';
import 'package:rooster/ui/organisms/dj/dj_booth_panel.dart';
import 'package:rooster/ui/organisms/soundboard/soundboard_call_controller.dart';
import 'package:rooster/utils/animation/ring_shaker.dart';
import 'package:rooster/utils/animation/ripple.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/avatar.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class CallView extends StatefulWidget {
  const CallView(
    this.currentSession, {
    this.setMicrophoneMute,
    this.setDeafened,
    this.pickScreenshareSource,
    this.stopScreenshare,
    this.pickCamera,
    this.disableCamera,
    this.hangUp,
    this.declineCall,
    this.acceptCall,
    super.key,
  });
  final VoipSession currentSession;

  static const Duration volumeAnimationDuration = Duration(milliseconds: 150);

  final Future<void> Function(bool)? setMicrophoneMute;
  final Future<void> Function(bool)? setDeafened;
  final Future<void> Function()? pickScreenshareSource;
  final Future<void> Function()? stopScreenshare;
  final Future<void> Function()? pickCamera;
  final Future<void> Function()? disableCamera;
  final Future<void> Function()? hangUp;
  final Future<void> Function()? declineCall;
  final Future<void> Function()? acceptCall;

  @override
  State<CallView> createState() => _CallViewState();
}

class _CallViewState extends State<CallView> {
  Timer? statTimer;
  StreamSubscription? sub;
  bool isMouseHovering = false;
  VoipStream? mainStream;
  late Room room;
  SoundboardCallController? _soundboard;
  bool _soundboardOpen = false;

  /// The DJ booth panel is open next to the call.
  bool _boothOpen = false;
  StreamSubscription? _boothSub;
  StreamSubscription? _boothPanelSub;
  DjSession? get _dj => DjBooths.of(widget.currentSession);

  @override
  void initState() {
    super.initState();
    sub = widget.currentSession.onStateChanged.listen((event) {
      setState(() {});
    });
    _boothSub = DjBooths.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
    // The DJ row in the sidebar opens the booth, before or after this view
    // is up.
    _boothOpen = DjBooths.takePanelRequest(widget.currentSession);
    _boothPanelSub = DjBooths.onPanelRequested.listen((session) {
      if (!mounted || session != widget.currentSession) return;
      DjBooths.takePanelRequest(session);
      setState(() => _boothOpen = true);
    });

    room = widget.currentSession.client.getRoom(widget.currentSession.roomId)!;
    statTimer = Timer.periodic(const Duration(milliseconds: 200), timer);

    // Soundboard: preload catalog audio on call join for instant click->play.
    _soundboard = SoundboardCallController.acquire(widget.currentSession);
  }

  @override
  void dispose() {
    statTimer?.cancel();
    sub?.cancel();
    _boothSub?.cancel();
    _boothPanelSub?.cancel();
    _soundboard?.release();
    _soundboard = null;
    super.dispose();
  }

  void timer(Timer timer) async {
    await widget.currentSession.updateStats();
  }

  @override
  Widget build(BuildContext context) {
    return tiamat.Tile.lowest(
      child: switch (widget.currentSession.state) {
        VoipState.connected => callConnectedView(),
        VoipState.outgoing => callOutgoingView(),
        VoipState.connecting => callOutgoingView(),
        VoipState.ended => callEndedView(),
        VoipState.incoming => callIncomingView(),
        _ => const Placeholder()
      },
    );
  }

  Widget callOutgoingView() {
    return callButtons(
      child: Center(
        child: RippleAnimation(
          ripplesCount: 3,
          scale: 1,
          color: Theme.of(context).colorScheme.primary,
          repeat: true,
          child: Avatar.large(
              image: room.avatar,
              placeholderColor: room.defaultColor,
              placeholderText: room.displayName),
        ),
      ),
    );
  }

  CallControlActions get controlActions => CallControlActions(
        setMicrophoneMute: widget.setMicrophoneMute,
        setDeafened: widget.setDeafened,
        pickScreenshareSource: widget.pickScreenshareSource,
        stopScreenshare: widget.stopScreenshare,
        pickCamera: widget.pickCamera,
        disableCamera: widget.disableCamera,
        hangUp: widget.hangUp,
        soundboard: _soundboard,
      );

  void showFullscreen(VoipStream stream) {
    VoipFullscreenStreamView.show(context,
        session: widget.currentSession,
        stream: stream,
        actions: controlActions);
  }

  Widget callButtons({bool connected = false, required Widget child}) {
    // Mobile keeps touch-sized buttons; the desktop row only shows on hover.
    final buttonRadius = MediaQuery.of(context).mobile ? 24.0 : 18.0;
    final buttonIconSize = buttonRadius * 1.2;
    return MouseRegion(
      onEnter: (event) {
        setState(() {
          isMouseHovering = true;
        });
      },
      onExit: (event) {
        setState(() {
          isMouseHovering = false;
        });
      },
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          child,
          AnimatedOpacity(
            // Stay visible while the soundboard popover is anchored here.
            opacity: MediaQuery.of(context).mobile ||
                    isMouseHovering ||
                    _soundboardOpen
                ? 1
                : 0,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              child: connected
                  ? CallControlButtons(
                      session: widget.currentSession,
                      actions: controlActions,
                      radius: buttonRadius,
                      boothOpen: _boothOpen,
                      onToggleBooth: _dj == null
                          ? null
                          : () => setState(() => _boothOpen = !_boothOpen),
                      onHungUp: () {
                        if (mounted) setState(() {});
                      },
                      onSoundboardOpenChanged: (open) {
                        if (mounted) setState(() => _soundboardOpen = open);
                      },
                    )
                  : tiamat.CircleButton(
                      color: Theme.of(context).colorScheme.errorContainer,
                      radius: buttonRadius,
                      iconSize: buttonIconSize,
                      icon: Icons.call_end,
                      onPressed: () async {
                        await widget.hangUp?.call();
                        setState(() {});
                      },
                    ),
            ),
          )
        ],
      ),
    );
  }

  Widget callConnectedView() {
    final dj = _dj;
    final call = callButtons(
        connected: true,
        // The now playing pill has a strip of its own above the tiles: over
        // them it hid the corner buttons (fullscreen) of a focused stream.
        child: Column(
          children: [
            dj != null && !_boothOpen
                ? DjNowPlayingPill(
                    dj: dj,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    onTap: () => setState(() => _boothOpen = true))
                : const SizedBox.shrink(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  var ratio = constraints.maxWidth / constraints.maxHeight;

                  if (ratio > 1) {
                    return Row(children: generateLayout());
                  } else {
                    return Column(children: generateLayout());
                  }
                },
              ),
            ),
          ],
        ));
    // One tree whether the booth is open or not, wide or narrow: the call's
    // tiles and video renderers must not be rebuilt by opening it.
    return LayoutBuilder(builder: (context, constraints) {
      final open = dj != null && _boothOpen;
      // Beside the call when there is room, over it otherwise.
      final beside = constraints.maxWidth >= 820;
      const boothWidth = 380.0;
      return Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            right: open && beside ? boothWidth : 0,
            child: call,
          ),
          if (open)
            Positioned(
              top: 0,
              // Over the call, it leaves the call's buttons (mute, hang up)
              // uncovered.
              bottom: beside ? 0 : 84,
              right: 0,
              left: beside ? null : 0,
              width: beside ? boothWidth : null,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: DjBoothPanel(
                    session: widget.currentSession,
                    dj: dj,
                    onClose: () => setState(() => _boothOpen = false),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  List<Widget> generateLayout() {
    final streams = widget.currentSession.streams;
    // The session can replace a stream object for the same publication (a
    // video muted and unmuted): keep the focused one pointing at the live
    // object, or drop it once the stream is gone.
    final focusedId = mainStream?.streamId;
    mainStream = focusedId == null
        ? null
        : streams.where((s) => s.streamId == focusedId).firstOrNull;
    final tiles = callGridTiles(streams);
    return [
      if (mainStream != null)
        Flexible(
          flex: 100,
          fit: FlexFit.tight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    mainStream = null;
                  });
                },
                child: VoipStreamView(
                  mainStream!,
                  widget.currentSession,
                  audioStream: tiles
                      .where((tile) => tile.stream == mainStream)
                      .firstOrNull
                      ?.audioStream,
                  borderColor: Colors.white,
                  onFullscreen: () => showFullscreen(mainStream!),
                  fit: BoxFit.contain,
                  key: ValueKey(
                      "callView_mainStreamView_${mainStream!.streamId}"),
                ),
              ),
            ),
          ),
        ),
      Flexible(
        fit: FlexFit.tight,
        flex: 75,
        child: Center(
          child: BentoLayout(
              tiles.where((tile) => tile.stream != mainStream).map((tile) {
            final e = tile.stream;
            return GestureDetector(
                onTap: () {
                  setState(() {
                    mainStream = e;
                  });
                },
                child: VoipStreamView(
                  key: ValueKey("callView__${e.streamId}"),
                  e,
                  audioStream: tile.audioStream,
                  fit: e.type == VoipStreamType.screenshare
                      ? BoxFit.contain
                      : BoxFit.cover,
                  widget.currentSession,
                  onFullscreen: () => showFullscreen(e),
                ));
          }).toList()),
        ),
      )
    ];
  }

  Widget callEndedView() {
    return const Center(child: tiamat.Text.label("Call ended"));
  }

  Widget callIncomingView() {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Center(
          child: RingShakerAnimation(
            child: Avatar.large(
                image: room.avatar,
                placeholderColor: room.defaultColor,
                placeholderText: room.displayName),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 5,
            children: [
              tiamat.CircleButton(
                icon: Icons.call,
                onPressed: () async {
                  await widget.acceptCall?.call();
                  setState(() {});
                },
              ),
              tiamat.CircleButton(
                icon: Icons.call_end,
                onPressed: () async {
                  await widget.declineCall?.call();
                  setState(() {});
                },
              )
            ],
          ),
        ),
      ],
    );
  }
}
