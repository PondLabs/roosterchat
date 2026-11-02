import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rooster/client/call_manager.dart';
import 'package:rooster/client/components/voip/voip_session.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/language/app_language.dart';
import 'package:rooster/utils/voice_controls/voice_controls.dart';

/// Tells every surface outside the window (tray, taskbar thumbnail, Dock
/// menu, launcher quicklist, browser panel) what the call looks like, and
/// only when that changes.
class VoiceCallWatcher {
  VoiceCallWatcher(this._calls);

  static final VoiceCallWatcher instance =
      VoiceCallWatcher(() => clientManager?.callManager);

  final CallManager? Function() _calls;

  VoiceCallState _state = VoiceCallState.idle;
  VoiceCallState get state => _state;

  final StreamController<VoiceCallState> _changes =
      StreamController.broadcast();
  Stream<VoiceCallState> get changes => _changes.stream;

  /// Whether we are being heard talking, once [watchSpeaking] was called.
  /// Apart from [state]: it flips with every word, and only the tray shows
  /// it.
  final ValueNotifier<bool> speaking = ValueNotifier(false);
  bool _watchingSpeaking = false;

  /// Starts following [speaking], five times a second while in a call.
  void watchSpeaking() {
    if (_watchingSpeaking) return;
    _watchingSpeaking = true;
    if (_started) _watchSessions();
  }

  bool _started = false;
  CallManager? _watching;
  final List<StreamSubscription> _listSubs = [];
  final List<StreamSubscription> _sessionSubs = [];
  Timer? _poll;

  /// Starts watching; later calls do nothing.
  ///
  /// Mute changes are announced by LiveKit sessions but not by legacy 1:1
  /// ones, and an app refresh replaces the call manager: [poll] catches both.
  void start({Duration? poll = const Duration(seconds: 1)}) {
    if (_started) return;
    _started = true;
    if (poll != null) _poll = Timer.periodic(poll, (_) => refresh());
    // The surfaces' labels are in the app's language, and none of them is
    // rebuilt with the window: a new language is told like a change of the
    // call, so they show it at once.
    AppLanguage.current.addListener(_languageChanged);
    refresh();
  }

  void _languageChanged() {
    if (_started) _changes.add(_state);
  }

  void stop() {
    _started = false;
    AppLanguage.current.removeListener(_languageChanged);
    _poll?.cancel();
    _poll = null;
    for (final sub in [..._listSubs, ..._sessionSubs]) {
      sub.cancel();
    }
    _listSubs.clear();
    _sessionSubs.clear();
    _watching = null;
    speaking.value = false;
  }

  /// Presses [control] as the surfaces show it: they all draw [state].
  void press(VoiceControl control) {
    final calls = _calls();
    if (calls == null) return;
    _state.press(control, calls);
    refresh();
  }

  /// Presses the control named [name] (a [VoiceControl] name), for surfaces
  /// that hand back strings: menus, D-Bus, method channels.
  void pressNamed(String name) {
    final control = VoiceControl.values.asNameMap()[name];
    if (control != null) press(control);
  }

  /// Reads the calls again, and tells the listeners if anything changed.
  void refresh() {
    if (!_started) return;
    final calls = _calls();
    if (!identical(calls, _watching)) _watch(calls);

    final state =
        VoiceCallState.of(calls?.currentSessions ?? const <VoipSession>[]);
    _readSpeaking();
    if (state == _state) return;
    _state = state;
    _changes.add(state);
  }

  void _watch(CallManager? calls) {
    for (final sub in _listSubs) {
      sub.cancel();
    }
    _listSubs.clear();
    _watching = calls;
    if (calls != null) {
      _listSubs.add(calls.currentSessions.onListUpdated.listen((_) {
        _watchSessions();
        refresh();
      }));
    }
    _watchSessions();
  }

  void _watchSessions() {
    for (final sub in _sessionSubs) {
      sub.cancel();
    }
    _sessionSubs.clear();
    for (final session in _watching?.currentSessions ?? const []) {
      _sessionSubs.add(session.onStateChanged.listen((_) => refresh()));
      if (_watchingSpeaking) {
        _sessionSubs.add(
            session.onUpdateVolumeVisualizers.listen((_) => _readSpeaking()));
      }
    }
    _readSpeaking();
  }

  void _readSpeaking() {
    if (!_watchingSpeaking) return;
    speaking.value = VoiceCallState.speaking(
        _watching?.currentSessions ?? const <VoipSession>[]);
  }
}
