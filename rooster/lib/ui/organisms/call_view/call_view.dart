import 'dart:async';
import 'package:rooster/client/components/call_activity/call_activity_component.dart';
import 'package:rooster/client/components/call_activity/call_activity_session.dart';
import 'package:rooster/client/components/dj/dj_session.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/client/matrix/components/call_activity/matrix_call_activity_component.dart';
import 'package:rooster/client/matrix/components/dj/dj_booths.dart';
import 'package:rooster/client/components/voip/voip_stream.dart';
import 'package:rooster/ui/atoms/appear_in.dart';
import 'package:rooster/client/room.dart';
import 'package:rooster/config/layout_config.dart';
import 'package:rooster/ui/layout/bento.dart';
import 'package:rooster/ui/organisms/call_view/call_control_buttons.dart';
import 'package:rooster/ui/organisms/call_view/call_focus.dart';
import 'package:rooster/ui/organisms/call_view/call_grid_tiles.dart';
import 'package:rooster/ui/organisms/call_view/voip_fullscreen_stream_view.dart';
import 'package:rooster/ui/organisms/call_view/voip_stream_view.dart';
import 'package:rooster/ui/organisms/call_activity/activity_join_pill.dart';
import 'package:rooster/ui/organisms/call_activity/activity_picker_panel.dart';
import 'package:rooster/ui/organisms/call_activity/activity_stage.dart';
import 'package:rooster/ui/organisms/dj/dj_booth_panel.dart';
import 'package:rooster/ui/organisms/soundboard/soundboard_call_controller.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_audio.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_launch_options.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/putt_session.dart';
import 'package:rooster/ui/organisms/sunny_side_putt/sunny_side_putt_game.dart';
import 'package:rooster/utils/animation/ring_shaker.dart';
import 'package:rooster/utils/animation/ripple.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  static String get labelCallEnded => Intl.message("Call ended",
      name: "labelCallEnded", desc: "Shown in place of a call that has ended");

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

  /// The grid's tiles, to pop in whoever joins while the call is on screen.
  final Arrivals arrivals = Arrivals();
  late Room room;
  SoundboardCallController? _soundboard;
  bool _soundboardOpen = false;

  /// The DJ booth panel is open next to the call.
  bool _boothOpen = false;

  /// The live call activity this call is playing (the game on the stage),
  /// the one the pill invites us into, and the sound they make.
  PuttSessionController? _activity;
  PuttAudio? _puttAudio;
  StreamSubscription? _activityStreamsSub;
  StreamSubscription? _boothSub;
  StreamSubscription? _boothPanelSub;
  StreamSubscription? _focusSub;
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
    // So does a click on someone live, who may be what opened this view.
    takeFocusRequest();
    _focusSub = CallFocus.onRequested.listen((session) {
      if (!mounted || session != widget.currentSession) return;
      setState(takeFocusRequest);
    });

    room = widget.currentSession.client.getRoom(widget.currentSession.roomId)!;
    statTimer = Timer.periodic(const Duration(milliseconds: 200), timer);

    // Soundboard: preload catalog audio on call join for instant click->play.
    _soundboard = SoundboardCallController.acquire(widget.currentSession);

    registerSunnySidePutt();
    // Activities: the call's stage follows a session's whole life
    // (started, joined, ended) through the room component's own stream.
    _activityStreamsSub = _activityComponent?.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _adoptExistingActivity();
  }

  MatrixCallActivityComponent? get _activityComponent =>
      room.getComponent<MatrixCallActivityComponent>();

  String _memberNameOf(String identity) {
    // A livekit identity is a matrix user id with (at most) a device
    // suffix; the member list knows the plain user id.
    final userId = identity.split(':').take(2).join(':');
    return room.getMemberOrFallback(userId).displayName;
  }

  ImageProvider? _memberAvatarOf(String identity) {
    final userId = identity.split(':').take(2).join(':');
    return room.getMemberOrFallback(userId).avatar;
  }

  /// Rejoining (or a view rebuilt): if we are already in a live session
  /// of this call, its stage comes back.
  void _adoptExistingActivity() {
    if (_activity != null) return;
    final component = _activityComponent;
    if (component == null) return;
    for (final entry in component.visibleSessions()) {
      final session = component.sessionOf(entry.sessionId);
      final mine = session != null &&
          (session.snapshot.players.contains(session.selfIdentity) ||
              session.snapshot.spectators.contains(session.selfIdentity));
      if (!mine) continue;
      _activity = PuttSessionController(
        session: session,
        nameOf: _memberNameOf,
        avatarOf: _memberAvatarOf,
        onEnded: () => _exitActivity(),
      );
      return;
    }
  }

  /// The live session of this call there is a seat in (the pill's
  /// subject), when we have not joined it yet.
  CallActivitySession? _joinableSession() {
    final activity = _activity;
    if (activity != null) return null;
    final component = _activityComponent;
    if (component == null) return null;
    for (final entry in component.visibleSessions()) {
      final session = component.sessionOf(entry.sessionId);
      if (session == null) continue;
      final seats = [
        ...session.snapshot.players,
        ...session.snapshot.spectators,
      ];
      if (seats.contains(session.selfIdentity)) continue;
      return session;
    }
    return null;
  }

  Future<void> _joinSession(CallActivitySession session) async {
    if (_activity != null) return;
    setState(() {
      _activity = PuttSessionController(
        session: session,
        nameOf: _memberNameOf,
        avatarOf: _memberAvatarOf,
        onEnded: () => _exitActivity(),
      );
    });
    await session.join();
  }

  Future<void> _launchActivity(CallActivity activity) async {
    final options = await showPuttLaunchOptions(context);
    if (!mounted || options == null) return;
    final component = _activityComponent;
    if (component == null) return;
    final session = await component.launch(activity);
    if (session == null || !mounted) return;
    final controller = PuttSessionController(
      session: session,
      nameOf: _memberNameOf,
      avatarOf: _memberAvatarOf,
      onEnded: () => _exitActivity(),
    );
    await controller.hostStart(PuttSessionController.buildConfig(options));
    setState(() => _activity = controller);
  }

  /// Out of the activity: back to the plain call (the session goes on
  /// without us — the host hands the seat over if we held it).
  Future<void> _exitActivity() async {
    final controller = _activity;
    if (controller == null) return;
    await controller.leave();
    controller.dispose();
    if (mounted) setState(() => _activity = null);
  }

  /// The activity shelf, over the call: what this app can play in the
  /// call, and the sessions already running in it.
  Future<void> _openActivityPicker() async {
    final component = _activityComponent;
    if (component == null) return;
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: ActivityPickerPanel(
          activities: CallActivityRegistry.all,
          liveSessions: component.visibleSessions(),
          nameOf: _memberNameOf,
          onLaunch: (activity) {
            Navigator.of(context).pop();
            _launchActivity(activity);
          },
          onJoin: (entry) {
            Navigator.of(context).pop();
            final session = component.sessionOf(entry.sessionId);
            if (session != null) _joinSession(session);
          },
        ),
      ),
    );
  }

  /// The call's videos as the stage's strip: the same views the grid
  /// builds, smaller, one row.
  Widget _activityStrip() {
    final streams = widget.currentSession.streams;
    final focusedId = mainStream?.streamId;
    final tiles = callGridTiles(streams);
    return SizedBox(
      height: 118,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: [
          for (final tile in tiles)
            if (tile.stream.streamId != focusedId)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: VoipStreamView(
                    key: ValueKey("callView_stripView_${tile.stream.streamId}"),
                    tile.stream,
                    widget.currentSession,
                    audioStream: tile.audioStream,
                    fit: tile.stream.type == VoipStreamType.screenshare
                        ? BoxFit.contain
                        : BoxFit.cover,
                    onFullscreen: () => showFullscreen(tile.stream),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    statTimer?.cancel();
    sub?.cancel();
    _boothSub?.cancel();
    _boothPanelSub?.cancel();
    _focusSub?.cancel();
    _activityStreamsSub?.cancel();
    _activity?.dispose();
    _puttAudio?.dispose();
    _soundboard?.release();
    _soundboard = null;
    super.dispose();
  }

  void timer(Timer timer) async {
    await widget.currentSession.updateStats();
  }

  /// Puts whoever the sidebar asked for in the middle, playing: nobody
  /// clicks on someone to then be asked whether to watch them.
  void takeFocusRequest() {
    final session = widget.currentSession;
    final userId = CallFocus.takeRequest(session);
    if (userId == null) return;
    final stream = CallFocus.streamOf(session.streams, userId);
    if (stream == null) return;
    mainStream = stream;
    stream.watch();
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
    // Touch keeps touch-sized buttons that are always there; with a mouse
    // the row only shows on hover. An unfolded foldable has the desktop
    // layout and no mouse: going by the layout hid its buttons for good.
    final touch = MediaQuery.sizeOf(context).touchControls;
    final buttonRadius = touch ? 24.0 : 18.0;
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
            opacity: touch || isMouseHovering || _soundboardOpen ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            // Above the iPhone's home indicator: the same 24 below the
            // buttons as before where there is none.
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: connected
                    ? CallControlButtons(
                        session: widget.currentSession,
                        actions: controlActions,
                        radius: buttonRadius,
                        compact: MediaQuery.sizeOf(context).mobile,
                        boothOpen: _boothOpen,
                        onToggleBooth: _dj == null
                            ? null
                            : () => setState(() => _boothOpen = !_boothOpen),
                        onActivitiesPressed: _openActivityPicker,
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
            ),
          )
        ],
      ),
    );
  }

  Widget callConnectedView() {
    // The activity owns the stage while we are in it; the call's controls
    // float on top of it, like over the tiles of a plain call.
    final activity = _activity;
    if (activity != null) {
      return ListenableBuilder(
        listenable: activity,
        builder: (context, _) => Stack(
          children: [
            Positioned.fill(
              child: ActivityStage(
                activityName: 'Sunny Side Putt',
                gameSlot: activity.match == null
                    ? null
                    : SunnySidePuttView(
                        match: activity.match!,
                        audio: _puttAudio ??= (PuttAudio()..preload()),
                        onLeave: () => _exitActivity(),
                      ),
                participantsStrip: _activityStrip(),
                onExit: () => _exitActivity(),
              ),
            ),
          ],
        ),
      );
    }
    final dj = _dj;
    final joinable = _joinableSession();
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
            joinable != null
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ActivityJoinPill(
                      activityName: 'Sunny Side Putt',
                      hostName: _memberNameOf(joinable.snapshot.hostUserId),
                      onJoin: () => _joinSession(joinable),
                    ))
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
              bottom: beside ? 0 : 84 + MediaQuery.paddingOf(context).bottom,
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
    // Someone who joins while the call is on screen pops into the grid.
    arrivals.update(tiles.map((tile) => tile.stream.streamId));
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
            return AppearIn(
              key: ValueKey("callView_appear_${e.streamId}"),
              play: arrivals.isNew(e.streamId),
              scale: 0.4,
              child: GestureDetector(
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
                  )),
            );
          }).toList()),
        ),
      )
    ];
  }

  Widget callEndedView() {
    return Center(child: tiamat.Text.label(CallView.labelCallEnded));
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
