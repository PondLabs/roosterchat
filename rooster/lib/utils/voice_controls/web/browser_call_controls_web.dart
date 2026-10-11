// The browser's side of the call controls outside the tab (issue #146):
// Media Session actions, and the Document Picture-in-Picture panel.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/atoms/voice_state_indicator.dart';
import 'package:rooster/utils/voice_controls/browser_call_controls.dart';
import 'package:rooster/utils/voice_controls/call_faces.dart';
import 'package:rooster/utils/voice_controls/call_members.dart';
import 'package:rooster/utils/voice_controls/voice_call_watcher.dart';
import 'package:rooster/utils/voice_controls/voice_controls.dart';
import 'package:rooster/utils/voice_controls/web/call_controls_panel.dart';
import 'package:rooster/utils/language/app_language.dart';
import 'package:web/web.dart' as web;

/// The Media Session members for calls, which package:web does not have.
/// `setMicrophoneActive` returns nothing in Chrome and a promise per the
/// spec.
extension type _CallMediaSession(JSObject _) implements JSObject {
  external void setActionHandler(String action, JSFunction? handler);
  external JSAny? setMicrophoneActive(bool active);
}

extension type _DocumentPictureInPicture(JSObject _) implements JSObject {
  external JSPromise<web.Window> requestWindow([JSObject? options]);
}

VoiceCallWatcher get _watcher => VoiceCallWatcher.instance;
StreamSubscription? _changes;
final Set<CallSessionAction> _handled = {};
CallControlsPanel? _panel;
web.Window? _panelWindow;
bool _opening = false;

/// Reads who is talking while the panel is open, as often as LiveKit says.
Timer? _membersFeed;
final CallFaces _faces = CallFaces();

/// Blob URLs of the avatars, by the image they were made from, and the
/// images being made into one.
final Map<ui.Image, String> _avatarUrls = {};
final Set<ui.Image> _encoding = {};

_CallMediaSession? get _mediaSession {
  final navigator = web.window.navigator as JSObject;
  if (!navigator.has("mediaSession")) return null;
  return _CallMediaSession(navigator["mediaSession"] as JSObject);
}

_DocumentPictureInPicture? get _documentPictureInPicture {
  if (!globalContext.has("documentPictureInPicture")) return null;
  return _DocumentPictureInPicture(
      globalContext["documentPictureInPicture"] as JSObject);
}

bool get canPopOut => _documentPictureInPicture != null;

Future<void> start() async {
  _watcher.start();
  _changes ??= _watcher.changes.listen(_apply);
  _apply(_watcher.state);
}

void _apply(VoiceCallState state) {
  final plan = MediaSessionPlan.of(state, canPopOut: canPopOut);
  final session = _mediaSession;
  if (session != null) {
    for (final action in CallSessionAction.values) {
      final wanted = plan.actions.contains(action);
      if (wanted == _handled.contains(action)) continue;
      try {
        session.setActionHandler(action.name, wanted ? _handler(action) : null);
        wanted ? _handled.add(action) : _handled.remove(action);
      } catch (_) {
        // Firefox throws for the call actions: it has none of them.
      }
    }

    final active = plan.microphoneActive;
    if (active != null) {
      try {
        final result = session.setMicrophoneActive(active);
        if (result != null && result.instanceOfString("Promise")) {
          // Safari may refuse to show unmuted without a click.
          (result as JSPromise).toDart.catchError((Object _) => null);
        }
      } catch (_) {
        // Not there (Firefox).
      }
    }
  }

  if (state.inCall) {
    _panel?.render(_buttons(state));
  } else {
    // Like the taskbar buttons, the panel goes when the call does.
    _panelWindow?.close();
    _panel = null;
    _panelWindow = null;
    _stopMembers();
  }
}

void _feedMembers() {
  _membersFeed ??= Timer.periodic(
      const Duration(milliseconds: 200), (_) => _renderMembers());
  _renderMembers();
}

void _stopMembers() {
  _membersFeed?.cancel();
  _membersFeed = null;
  for (final url in _avatarUrls.values) {
    web.URL.revokeObjectURL(url);
  }
  _avatarUrls.clear();
}

void _renderMembers() {
  final panel = _panel;
  if (panel == null) return;
  final session = clientManager?.callManager.currentSessions
      .firstWhereOrNull(VoiceCallState.isIn);
  if (session == null) {
    panel.renderMembers(const []);
    return;
  }
  // A legacy 1:1 call only reads its levels when asked; LiveKit's does
  // nothing here.
  if (session is! CallRoster) session.updateStats();
  panel.renderMembers([
    for (final member in CallMember.of(session))
      _listed(member, _faces.of(session, member.userId)),
  ]);
}

PanelMember _listed(CallMember member, CallFace face) => PanelMember(
      id: member.userId,
      name: face.name ?? member.userId,
      avatarUrl: _urlOf(face.avatar),
      talking: member.talking,
      deafened: member.deafened,
      silentLabel: member.deafened
          ? VoiceStateIndicator.tooltipVoiceDeafened
          : member.muted
              ? VoiceStateIndicator.tooltipVoiceMuted
              : null,
    );

/// [image] as a URL the panel's document can load, once it has been made.
String? _urlOf(ui.Image? image) {
  if (image == null) return null;
  final url = _avatarUrls[image];
  if (url != null || !_encoding.add(image)) return url;
  image.toByteData(format: ui.ImageByteFormat.png).then((bytes) {
    if (bytes == null || _membersFeed == null) return;
    final png = bytes.buffer
        .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    _avatarUrls[image] = web.URL.createObjectURL(web.Blob([png.toJS].toJS));
  }).catchError((Object e) {
    Log.w("Could not show an avatar in the call controls: $e");
  }).whenComplete(() => _encoding.remove(image));
  return null;
}

JSFunction _handler(CallSessionAction action) => switch (action) {
      CallSessionAction.toggleMicrophone =>
        ((JSAny? _) => _watcher.press(VoiceControl.mute)).toJS,
      CallSessionAction.hangUp =>
        ((JSAny? _) => _watcher.press(VoiceControl.disconnect)).toJS,
      CallSessionAction.enterPictureInPicture => ((JSAny? _) => popOut()).toJS,
    };

List<PanelButton> _buttons(VoiceCallState state) => [
      for (final button in state.controls)
        PanelButton(
            id: button.control.name,
            active: button.active,
            label: button.label),
    ];

/// Opens the panel. The browser only allows this during a click, or in
/// Chrome's `enterpictureinpicture` handler, so nothing may be awaited
/// before `requestWindow`.
void popOut() {
  final pictureInPicture = _documentPictureInPicture;
  if (pictureInPicture == null ||
      _panelWindow != null ||
      _opening ||
      !_watcher.state.inCall) {
    return;
  }

  _opening = true;
  // Room for the buttons and about six people; it can be resized.
  final options = {"width": 240, "height": 264}.jsify() as JSObject;
  pictureInPicture.requestWindow(options).toDart.then((window) {
    _panelWindow = window;
    final panel = _panel = CallControlsPanel(window.document,
        onPress: _watcher.pressNamed,
        title: BuildConfig.app,
        language: AppLanguage.current.value.tag);
    panel.render(_buttons(_watcher.state));
    _feedMembers();
    window.addEventListener(
        "pagehide",
        ((web.Event _) {
          if (_panelWindow == window) {
            _panel = null;
            _panelWindow = null;
            _stopMembers();
          }
        }).toJS);
  }, onError: (Object e) {
    Log.w("Could not pop out the call controls: $e");
  }).whenComplete(() => _opening = false);
}
