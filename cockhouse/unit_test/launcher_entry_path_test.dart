// The launcher badge's D-Bus object path. The launcher_entry package's own
// default hashes the app URI into a signed int, which is negative for
// com.pondlabs.cockhouse: the `-` made the path invalid, and every badge
// update threw (it failed the integration tests on the rename to Cockhouse).
import 'package:cockhouse/client/components/push_notification/linux/linux_notifier.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the path is valid for this app', () {
    final path = LinuxNotifier.launcherEntryObjectPath(
        'application://com.pondlabs.cockhouse.desktop');
    expect(path, matches(RegExp(r'^/com/canonical/unity/launcherentry/\d+$')));
    expect(() => DBusObjectPath(path), returnsNormally);
  });

  test('it is GLib\'s string hash, as libunity names it', () {
    // g_str_hash: djb2 over the bytes, 32 bits unsigned.
    expect(
        LinuxNotifier.launcherEntryObjectPath(
            'application://com.pondlabs.cockhouse.desktop'),
        '/com/canonical/unity/launcherentry/2460150923');
    expect(
        LinuxNotifier.launcherEntryObjectPath(
            'application://chat.commet.commetapp.desktop'),
        '/com/canonical/unity/launcherentry/3207632352');
  });
}
