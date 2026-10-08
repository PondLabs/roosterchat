import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

// Browsers omit mediaDevices on insecure origins. Text login still works.
bool get supportsMediaCapture =>
    web.window.navigator.getProperty<JSAny?>('mediaDevices'.toJS) != null;
