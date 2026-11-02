// Whether this platform can capture the screen at all. Every desktop and the
// Android app can; a browser only where it has getDisplayMedia, which the
// browsers on phones and tablets (Chrome and Firefox on Android, Safari on
// iOS) do not: there the share button used to be shown, and did nothing.
import 'screen_capture_support_native.dart'
    if (dart.library.js_interop) 'screen_capture_support_web.dart' as impl;

bool get canCaptureScreen => impl.canCaptureScreen;
