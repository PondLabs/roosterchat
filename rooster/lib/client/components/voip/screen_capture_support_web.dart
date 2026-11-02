import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Asked of the browser, not guessed from its name: one that gains
/// getDisplayMedia starts sharing without a change here. `mediaDevices`
/// itself is missing on a page not served over HTTPS.
bool get canCaptureScreen {
  final devices = (web.window.navigator as JSObject)
      .getProperty<JSAny?>('mediaDevices'.toJS);
  if (devices == null || !devices.isA<JSObject>()) return false;
  final capture =
      (devices as JSObject).getProperty<JSAny?>('getDisplayMedia'.toJS);
  return capture.isA<JSFunction>();
}
