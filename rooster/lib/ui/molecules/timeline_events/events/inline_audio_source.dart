/// Where the inline audio player reads a message's sound from, fetched
/// only when the person presses play: on desktop and mobile the file the
/// cache keeps (downloaded and decrypted by its provider), in the browser
/// the bytes behind a `blob:` URL of this page.
library;

export 'inline_audio_source_io.dart'
    if (dart.library.js_interop) 'inline_audio_source_web.dart';
