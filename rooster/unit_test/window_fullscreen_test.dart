// Fullscreen on Windows, reported with a screenshot: watching a stream
// fullscreen gave a maximized window, title bar and taskbar still there.
// window_manager only takes the frame off a window that is not maximized,
// and the app is usually kept maximized.
import 'package:rooster/utils/window_management.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('window_manager');
  late List<String> calls;
  late bool maximized;
  late bool fullscreen;

  /// How many times the window still says it is maximized after being asked
  /// to restore: the restore is posted, not done when the call returns.
  late int restoreLag;

  setUp(() {
    calls = [];
    maximized = false;
    fullscreen = false;
    restoreLag = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isFullScreen':
          return fullscreen;
        case 'isMaximized':
          if (restoreLag > 0) {
            restoreLag--;
            return true;
          }
          return maximized;
        case 'unmaximize':
          calls.add('unmaximize');
          maximized = false;
          return null;
        case 'maximize':
          calls.add('maximize');
          maximized = true;
          return null;
        case 'setFullScreen':
          fullscreen = (call.arguments as Map)['isFullScreen'] as bool;
          // What the plugin does to a maximized window: not fullscreen.
          calls.add(fullscreen && maximized
              ? 'fullscreen of a maximized window'
              : 'setFullScreen($fullscreen)');
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('on Windows', () {
    test('a maximized window is restored before it goes fullscreen', () async {
      maximized = true;

      await WindowManagement.setFullScreen(true, windows: true);

      expect(calls, ['unmaximize', 'setFullScreen(true)']);
    });

    test('and waits for the restore to land', () async {
      maximized = true;
      restoreLag = 3;

      await WindowManagement.setFullScreen(true, windows: true);

      expect(calls, ['unmaximize', 'setFullScreen(true)']);
    });

    test('and is maximized again when fullscreen ends', () async {
      maximized = true;
      await WindowManagement.setFullScreen(true, windows: true);
      calls.clear();

      await WindowManagement.setFullScreen(false, windows: true);

      expect(calls, ['setFullScreen(false)', 'maximize']);
    });

    test('a window that was not maximized is left as it was', () async {
      await WindowManagement.setFullScreen(true, windows: true);
      await WindowManagement.setFullScreen(false, windows: true);

      expect(calls, ['setFullScreen(true)', 'setFullScreen(false)']);
    });

    test('asking for what it already is does nothing', () async {
      await WindowManagement.setFullScreen(false, windows: true);
      fullscreen = true;
      await WindowManagement.setFullScreen(true, windows: true);

      expect(calls, isEmpty);
    });
  });

  test('elsewhere the window manager is asked as it is', () async {
    maximized = true;

    await WindowManagement.setFullScreen(true, windows: false);

    expect(calls, ['fullscreen of a maximized window']);
  });
}
