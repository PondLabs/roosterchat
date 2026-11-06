import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:media_kit_video/media_kit_video.dart'
    show defaultEnterNativeFullscreen, defaultExitNativeFullscreen;
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:window_manager/window_manager.dart';

import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/utils/window_management.dart';

/// Puts the app window (the browser tab on web) into fullscreen and gives
/// back what it found, like voip_fullscreen_stream_view's _NativeFullscreen.
class _StageFullscreen {
  _StageFullscreen._(this._entered);

  final Future<bool> _entered;

  static _StageFullscreen enter() => _StageFullscreen._(_enter());

  /// Whether this stage switched fullscreen on, and so should switch it off.
  static Future<bool> _enter() async {
    try {
      if (ActivityStage.debugSetFullscreen case final set?) {
        // Tests: no window to fill (the plugin channels stand empty under
        // the test runner). Answers whether it was already fullscreen.
        return !await set(true);
      }
      if (PlatformUtils.isLinux || PlatformUtils.isWindows) {
        // Already fullscreen (F11): leave it that way when the stage goes.
        if (await windowManager.isFullScreen()) return false;
        await WindowManagement.setFullScreen(true);
        return true;
      }
      if (PlatformUtils.isWeb) {
        await defaultEnterNativeFullscreen();
        return true;
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to enter the stage's fullscreen");
    }
    return false;
  }

  Future<void> exit() async {
    if (!await _entered) return;
    try {
      if (ActivityStage.debugSetFullscreen case final set?) {
        await set(false);
        return;
      }
      if (PlatformUtils.isLinux || PlatformUtils.isWindows) {
        await WindowManagement.setFullScreen(false);
      } else if (PlatformUtils.isWeb) {
        await defaultExitNativeFullscreen();
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to leave the stage's fullscreen");
    }
  }
}

/// The stage a call activity takes over: the activity's view in the middle
/// ([gameSlot], null before the game's ticket plugs it in - a placeholder
/// holds the slot), the call's videos as a compact strip under it, a
/// fullscreen toggle on desktop, and the easy exit (Esc, or the exit
/// button while the placeholder holds the slot: a game's own menu has its
/// leave, so the stage shows no second way out over it).
class ActivityStage extends StatefulWidget {
  const ActivityStage({
    required this.activityName,
    required this.participantsStrip,
    required this.onExit,
    this.gameSlot,
    super.key,
  });

  /// The hosted activity's display name, over the game.
  final String activityName;

  /// The activity's own view. Null before the game's ticket plugs it in,
  /// which keeps the slot ready with a placeholder.
  final Widget? gameSlot;

  /// The call's videos beside or under the game, however small the screen
  /// wants them (the call view reuses the tiles it already builds).
  final Widget participantsStrip;

  /// The easy exit: Esc, or the button before the game is in. Whatever
  /// mounted the stage drops it.
  final VoidCallback onExit;

  /// Whether the window a fullscreen would fill is one we can fill (a
  /// desktop window, a browser tab). A phone has neither to fill usefully.
  static bool get hasFullscreen =>
      PlatformUtils.isLinux || PlatformUtils.isWindows || PlatformUtils.isWeb;

  /// Tests: the window's fullscreen, without a window (the plugin channels
  /// stand empty under the test runner). Answers whether it was already
  /// fullscreen, as the window manager would.
  static Future<bool> Function(bool on)? debugSetFullscreen;

  @override
  State<ActivityStage> createState() => _ActivityStageState();
}

class _ActivityStageState extends State<ActivityStage> {
  _StageFullscreen? _fullscreen;
  bool get _isFullscreen => _fullscreen != null;

  /// The way out of fullscreen, floating over the game: up while the
  /// pointer moves, gone once it rests, so the game has the screen to
  /// itself (the call's screen share does the same).
  bool _controlsUp = true;
  Timer? _controlsTimer;
  static const _controlsTimeout = Duration(milliseconds: 2500);

  void _wakeControls() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(_controlsTimeout, () {
      if (mounted) setState(() => _controlsUp = false);
    });
    if (!_controlsUp) setState(() => _controlsUp = true);
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      final leaving = _fullscreen!;
      if (mounted) setState(() => _fullscreen = null);
      await leaving.exit();
      return;
    }
    final entered = await _StageFullscreen.enter();
    if (mounted && await entered._entered) {
      setState(() => _fullscreen = entered);
      _wakeControls();
    }
  }

  /// Esc leaves fullscreen first, then the stage, like the header's exit
  /// button.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_isFullscreen) {
        _toggleFullscreen();
        return KeyEventResult.handled;
      }
      widget.onExit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Material(
        color: colors.surface,
        child: _isFullscreen ? _fullscreenBody(context) : _stageBody(context),
      ),
    );
  }

  /// The stage as the call shows it: the header, the game, the videos.
  Widget _stageBody(BuildContext context) {
    return Column(
      children: [
        _header(context),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: widget.gameSlot ?? _placeholder(context),
          ),
        ),
        widget.participantsStrip,
      ],
    );
  }

  /// Fullscreen: the game edge to edge, the stage's own chrome gone - the
  /// header, the videos and the padding with them. The game keeps its own
  /// menu (its settings, its leave), so the Rooster options stay reachable
  /// over the fullscreen game, as they do over a fullscreen screen share.
  Widget _fullscreenBody(BuildContext context) {
    return MouseRegion(
      onHover: (_) => _wakeControls(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.gameSlot ?? _placeholder(context),
          Positioned(
            right: 8,
            bottom: 8,
            child: SafeArea(
              child: IgnorePointer(
                ignoring: !_controlsUp,
                child: AnimatedOpacity(
                  opacity: _controlsUp ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IconButton(
                    tooltip: ActivityStageStrings.exitFullscreen,
                    icon: const Icon(Icons.fullscreen_exit_rounded),
                    onPressed: _toggleFullscreen,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.55),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: tiamat.Text.largeTitle(widget.activityName),
          ),
          if (ActivityStageStrings.hasFullscreen)
            IconButton(
              tooltip: ActivityStageStrings.toggleFullscreen,
              icon: Icon(_isFullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded),
              onPressed: _toggleFullscreen,
            ),
          if (widget.gameSlot == null)
            IconButton(
              tooltip: ActivityStageStrings.leave,
              icon: const Icon(Icons.close_rounded),
              onPressed: widget.onExit,
            ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Center(
      child: Text(
        ActivityStageStrings.loading(widget.activityName),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

/// Strings of the stage host, for the tests to find by name.
abstract final class ActivityStageStrings {
  static String loading(String activity) => Intl.message("Loading $activity",
      name: "ActivityStageStrings_loading",
      args: [activity],
      desc: "Placeholder where the activity's view goes while it loads");

  static String get toggleFullscreen => Intl.message("Fullscreen",
      name: "ActivityStageStrings_toggleFullscreen",
      desc: "Toggle that fills the app window with the stage");

  static String get exitFullscreen => Intl.message("Exit fullscreen",
      name: "ActivityStageStrings_exitFullscreen",
      desc: "Button that leaves the stage's fullscreen and shows the call "
          "again");

  static String get leave => Intl.message("Exit",
      name: "ActivityStageStrings_leave",
      desc: "Button that leaves the stage and returns to the call's videos");

  /// Whether the window a fullscreen would fill is one we can fill (a
  /// desktop window, a browser tab). A phone has neither to fill usefully.
  static bool get hasFullscreen => ActivityStage.hasFullscreen;
}
