// Closing a Rooster on Windows, and what the next launch then finds
// (window_management.dart, single_instance.dart, and
// windows/runner/instance_lock.h for the lock itself).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/single_instance.dart';
import 'package:rooster/utils/window_management.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final window = <String>[];
  final lock = <String>[];

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const windowChannel = MethodChannel('window_manager');
    const lockChannel = MethodChannel('com.pondlabs.rooster/instance');
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      window.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(lockChannel, (call) async {
      lock.add(call.method);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(windowChannel, null);
      messenger.setMockMethodCallHandler(lockChannel, null);
      window.clear();
      lock.clear();
    });
  });

  test('only the main instance on Windows gives the lock up, and once',
      () async {
    await SingleInstance.leave(windows: true);
    expect(lock, isEmpty, reason: 'a second copy never held it');

    // ignore: invalid_use_of_visible_for_testing_member
    SingleInstance.isMainInstance = true;
    await SingleInstance.leave(windows: false);
    expect(lock, isEmpty, reason: 'the lock is the Windows runner\'s');

    await SingleInstance.leave(windows: true);
    await SingleInstance.leave(windows: true);
    expect(lock, ['leave']);
  });

  // Last: closing latches for the life of the process.
  test(
      'restarting into an update from the loading window keeps the window '
      'up and the lock held', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SingleInstance.isMainInstance = true;
    await WindowManagement.showLauncher();
    window.clear();

    await WindowManagement.close(restarting: true);

    expect(window, isNot(contains('hide')),
        reason: 'it says "Restarting into…" until the process ends');
    expect(window, contains('destroy'));
    expect(lock, isEmpty,
        reason: 'a click meanwhile must not start the build being replaced');

    await WindowManagement.bringToFront();
    expect(window, isNot(contains('show')),
        reason: 'a window on its way out is not brought back');
  });
}
