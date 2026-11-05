// The Flutter test runner's mark, read where dart:io exists (native and
// flutter test): widget tests drive the putter headlessly, so the 3D
// surface must not come up there (the test runner's process carries no GL
// and the plugin channels stand empty - see `PuttThreeSurface`).
library;

import 'dart:io';

bool get runningUnderFlutterTest =>
    Platform.environment.containsKey('FLUTTER_TEST');
