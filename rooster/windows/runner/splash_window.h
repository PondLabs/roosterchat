#ifndef RUNNER_SPLASH_WINDOW_H_
#define RUNNER_SPLASH_WINDOW_H_

#include <windows.h>

// ROOSTER: the loading square, up from the moment Rooster is clicked. The
// Flutter window stays hidden until Dart has drawn its first frame, which on
// a cold start (the engine, the plugins, Dart's own start) took seconds with
// nothing on screen. This stands in, at the size and place main.dart's
// loading window takes, until that frame. Returns null if it could not be
// made; nothing depends on it.
HWND ShowSplashWindow();

#endif  // RUNNER_SPLASH_WINDOW_H_
