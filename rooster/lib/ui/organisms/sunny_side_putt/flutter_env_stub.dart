// The web stub of the test-runner check: on web there is no `FLUTTER_TEST`
// mark to read (and no dart:io to read it with); the renderer only needs
// WebGL2, so the surface always tries.
library;

bool get runningUnderFlutterTest => false;
