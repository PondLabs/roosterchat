import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/call_manager.dart';
import 'package:rooster/client/components/push_notification/notification_content.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/game_overlay/overlay_painter.dart';
import 'package:rooster/utils/voice_controls/call_faces.dart';
import 'package:rooster/utils/voice_controls/call_members.dart';
import 'package:rooster/utils/voice_controls/voice_controls.dart';

/// The overlay's panels. The index is the runner's id for it, and the order
/// panels sharing a corner stack in from it.
enum OverlayPanel { voice, messages }

/// A corner of the game's screen, as the preferences store it.
enum OverlayCorner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get isRight => this == topRight || this == bottomRight;
}

typedef VoicePanelDrawer = Future<OverlayImage> Function(
    List<OverlayMember> members,
    {String? more,
    required double scale,
    bool alignEnd});

typedef ToastsDrawer = Future<OverlayImage> Function(List<OverlayToast> toasts,
    {required double scale});

/// The in-game overlay on Windows, as Discord has it: who is in the call and
/// who is talking, and the messages that would notify, over a game running
/// fullscreen or borderless (docs/game-overlay.md).
///
/// The runner (windows/runner/game_overlay.cpp) shows each panel in its own
/// small click-through window and says when such a game is in front; this
/// decides what the panels say and draws them.
class GameOverlay {
  GameOverlay({
    MethodChannel? channel,
    CallManager? Function()? calls,
    VoicePanelDrawer? drawVoice,
    ToastsDrawer? drawMessages,
    AvatarDrawer? drawAvatar,
    this.tick = const Duration(milliseconds: 200),
    this.toastTime = const Duration(seconds: 6),
  })  : _channel = channel ?? const MethodChannel(channelName),
        _calls = calls ?? (() => clientManager?.callManager),
        _drawVoice = drawVoice ?? drawVoicePanel,
        _drawMessages = drawMessages ?? drawToasts,
        _faces = CallFaces(drawAvatar: drawAvatar);

  static const channelName = "com.pondlabs.rooster/overlay";

  static final GameOverlay instance = GameOverlay();

  static bool get supported => PlatformUtils.isWindows;

  /// How many people the call's list shows before it says how many more.
  static const maxMembers = 8;

  static const maxToasts = 3;

  static String labelOverlayMoreMembers(int howMany) => Intl.plural(howMany,
      one: "1 more",
      other: "$howMany more",
      name: "labelOverlayMoreMembers",
      args: [howMany],
      desc: "Last row of the in-game overlay's list of who is in the call, "
          "for the people who did not fit");

  /// How often the call is read while a game is in front: as often as
  /// LiveKit reports who is talking.
  final Duration tick;
  final Duration toastTime;

  final MethodChannel _channel;
  final CallManager? Function() _calls;
  final VoicePanelDrawer _drawVoice;
  final ToastsDrawer _drawMessages;
  final CallFaces _faces;

  final List<StreamSubscription> _subs = [];
  bool _started = false;
  bool _gameInFront = false;
  double _scale = 1;
  Timer? _ticker;

  /// What the call's panel shows now (null: nothing), and the draws in
  /// flight, so a slow one does not land after a newer one.
  (List<OverlayMember>, OverlayCorner)? _voice;
  int _voiceDraws = 0;

  /// Draw the call's panel again even if it says the same: the screen's
  /// scale or the settings changed.
  bool _redrawVoice = false;

  final List<OverlayToast> _toasts = [];
  int _toastDraws = 0;

  Future<void> start() async {
    _channel.setMethodCallHandler(_onRunnerCall);
    _subs.addAll([
      preferences.gameOverlayEnabled.onChanged.listen((_) => _applyEnabled()),
      preferences.gameOverlayVoiceCorner.onChanged.listen((_) => _restyle()),
      preferences.gameOverlayOnlyTalking.onChanged.listen((_) => _restyle()),
      preferences.gameOverlayMessageCorner.onChanged.listen((_) => _restyle()),
    ]);
    await _applyEnabled();
  }

  Future<void> stop() async {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _channel.setMethodCallHandler(null);
    if (_started) {
      _started = false;
      _onGame(null);
      await _channel.invokeMethod("stop");
    }
  }

  /// Shows [message] over the game, if one is in front. It returns at once
  /// and never throws: the system's own notification is shown either way.
  void showMessage(MessageNotificationContent message) {
    try {
      if (!_gameInFront || _messageCorner == null || _sharingScreen) return;
      _addToast(message).catchError((Object e, StackTrace s) {
        Log.onError(e, s, content: "Could not show a message over the game");
      });
    } catch (e, s) {
      Log.onError(e, s, content: "Could not show a message over the game");
    }
  }

  OverlayCorner get _voiceCorner =>
      OverlayCorner.values
          .asNameMap()[preferences.gameOverlayVoiceCorner.value] ??
      OverlayCorner.topLeft;

  /// Null when messages are off.
  OverlayCorner? get _messageCorner =>
      OverlayCorner.values
          .asNameMap()[preferences.gameOverlayMessageCorner.value];

  /// The call we are in: the first one, as the other surfaces outside the
  /// window take it.
  VoipSession? get _session =>
      _calls()?.currentSessions.firstWhereOrNull(VoiceCallState.isIn);

  /// A share of the whole screen would carry the messages to everyone
  /// watching it: the overlay is not hidden from screen capture, because
  /// hiding from it is what cheats do.
  bool get _sharingScreen =>
      _calls()?.currentSessions.any(
          (s) => VoiceCallState.isIn(s) && s.isSharingScreen) ==
      true;

  Future<void> _applyEnabled() async {
    final enabled = preferences.gameOverlayEnabled.value;
    if (enabled == _started) return;
    _started = enabled;
    if (enabled) {
      final state = await _channel.invokeMapMethod<String, Object?>("start");
      if (_started) _onGame(state);
    } else {
      _onGame(null);
      await _channel.invokeMethod("stop");
    }
  }

  Future<void> _onRunnerCall(MethodCall call) async {
    if (call.method == "onGameChanged" && _started) {
      _onGame((call.arguments as Map).cast<String, Object?>());
    }
  }

  void _onGame(Map<String, Object?>? state) {
    final inFront = state?["inFront"] == true;
    final scale = (state?["scale"] as num?)?.toDouble() ?? 1;
    if (inFront == _gameInFront && scale == _scale) return;
    _gameInFront = inFront;
    _scale = scale;

    if (inFront) {
      _ticker ??= Timer.periodic(tick, (_) => _readCall());
      _redrawVoice = true;
      _readCall();
      if (_toasts.isNotEmpty) _logged(_showToasts());
    } else {
      // The runner has hidden the panels already. Dropping them here keeps
      // the next game from flashing what this one showed.
      _ticker?.cancel();
      _ticker = null;
      _toasts.clear();
      _setVoice(null);
      _logged(_showToasts());
    }
  }

  void _restyle() {
    if (!_gameInFront) return;
    _redrawVoice = true;
    _readCall();
    _logged(_showToasts());
  }

  void _readCall() {
    if (_sharingScreen && _toasts.isNotEmpty) {
      _toasts.clear();
      _logged(_showToasts());
    }

    final session = _session;
    if (session == null) {
      _setVoice(null);
      return;
    }
    // A legacy 1:1 call only reads its levels when asked; LiveKit's does
    // nothing here.
    if (session is! CallRoster) session.updateStats();

    var members = CallMember.of(session);
    if (preferences.gameOverlayOnlyTalking.value) {
      members = members.where((m) => m.talking && !m.muted).toList();
    }
    _setVoice([
      for (final member in members)
        _drawn(member, _faces.of(session, member.userId)),
    ]);
  }

  static OverlayMember _drawn(CallMember member, CallFace face) =>
      OverlayMember(
          name: face.name ?? member.userId,
          avatar: face.avatar,
          talking: member.talking,
          muted: member.muted,
          deafened: member.deafened);

  void _setVoice(List<OverlayMember>? members) {
    final corner = _voiceCorner;
    final shown = members == null || members.isEmpty ? null : members;
    final last = _voice;
    final same = shown == null
        ? last == null
        : last != null &&
            last.$2 == corner &&
            const ListEquality<OverlayMember>().equals(last.$1, shown);
    if (same && !_redrawVoice) return;
    _redrawVoice = false;
    _voice = shown == null ? null : (shown, corner);
    final draw = ++_voiceDraws;
    _logged(() async {
      if (shown == null) {
        await _removePanel(OverlayPanel.voice);
        return;
      }
      final more = shown.length - maxMembers;
      final image = await _drawVoice(shown.take(maxMembers).toList(),
          more: more > 0 ? labelOverlayMoreMembers(more) : null,
          scale: _scale,
          alignEnd: corner.isRight);
      if (draw != _voiceDraws || !_gameInFront) return;
      await _setPanel(OverlayPanel.voice, corner, image);
    }());
  }

  Future<void> _addToast(MessageNotificationContent message) async {
    final room = clientManager
        ?.getClient(message.clientId)
        ?.getRoom(message.roomId);
    final avatar = await _faces.avatar(
        color: room?.getColorOfUser(message.senderId) ?? Colors.grey,
        name: message.senderName,
        image: message.senderImage);
    if (!_gameInFront) return;

    final toast = OverlayToast(
        sender: message.senderName,
        room: message.isDirectMessage ? null : message.roomName,
        body: message.content,
        avatar: avatar);
    _toasts.add(toast);
    while (_toasts.length > maxToasts) {
      _toasts.removeAt(0);
    }
    Timer(toastTime, () {
      if (_toasts.remove(toast)) _logged(_showToasts());
    });
    await _showToasts();
  }

  Future<void> _showToasts() async {
    final draw = ++_toastDraws;
    final corner = _messageCorner;
    if (_toasts.isEmpty || corner == null || !_gameInFront) {
      await _removePanel(OverlayPanel.messages);
      return;
    }
    final image = await _drawMessages(List.of(_toasts), scale: _scale);
    if (draw != _toastDraws || !_gameInFront) return;
    await _setPanel(OverlayPanel.messages, corner, image);
  }

  Future<void> _setPanel(
          OverlayPanel panel, OverlayCorner corner, OverlayImage image) =>
      _channel.invokeMethod("setPanel", {
        "id": panel.index,
        "corner": corner.name,
        "width": image.width,
        "height": image.height,
        "pixels": image.rgba,
      });

  Future<void> _removePanel(OverlayPanel panel) =>
      _channel.invokeMethod("removePanel", {"id": panel.index});

  void _logged(Future<void> work) {
    work.catchError((Object e, StackTrace s) {
      Log.onError(e, s, content: "Could not update the in-game overlay");
    });
  }
}
