// createSoundboardBroadcast for the platform: a custom WebRTC source fed by
// rust/dj_audio's board on desktop, Web Audio in the browser.
export 'native/soundboard_broadcast_native.dart'
    if (dart.library.js_interop) 'web/soundboard_broadcast_web.dart';
