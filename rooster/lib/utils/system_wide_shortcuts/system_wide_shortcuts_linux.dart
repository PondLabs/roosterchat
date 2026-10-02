import 'package:rooster/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:rooster/utils/voice_controls/voice_call_watcher.dart';
import 'package:rooster/utils/voice_controls/voice_controls.dart';
import 'package:dbus/dbus.dart';

// for testing:
// gdbus call --session --dest com.pondlabs.rooster --object-path /com/pondlabs/rooster/Shortcuts --method com.pondlabs.rooster.Shortcuts.unmute
// gdbus call --session --dest com.pondlabs.rooster --object-path /com/pondlabs/rooster/Shortcuts --method com.pondlabs.rooster.Shortcuts.mute
//
// `rooster --shortcut <method>` makes the same call (linux/shortcuts.h), which
// is what the desktop file's actions run.

class SystemWideShortcutsLinux {
  static Future<void> init() async {
    await initDbus();
  }

  static Future<void> initDbus() async {
    var client = DBusClient.session();
    await client.requestName('com.pondlabs.rooster');
    await client.registerObject(ShortcutsObject());
  }
}

class ShortcutsObject extends DBusObject {
  ShortcutsObject({VoiceCallWatcher? calls})
      : _calls = calls ?? VoiceCallWatcher.instance,
        super(DBusObjectPath('/com/pondlabs/rooster/Shortcuts'));

  final VoiceCallWatcher _calls;

  /// The system-wide shortcuts, and leaving the call, which the desktop
  /// file's Disconnect action asks for (issue #146).
  static Iterable<String> get methods =>
      [...SystemWideShortcuts.shortcuts.keys, VoiceControl.disconnect.name];

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'com.pondlabs.rooster.shortcuts' && name == 'Version') {
      return DBusGetPropertyResponse(DBusString('1.0'));
    } else {
      return DBusMethodErrorResponse.unknownProperty();
    }
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    print("Handling dbus message call!");
    print(methodCall.toString());
    if (methodCall.interface != "com.pondlabs.rooster.Shortcuts") {
      return DBusMethodErrorResponse.unknownInterface();
    }

    var shortcut = SystemWideShortcuts.shortcuts[methodCall.name];

    if (shortcut != null) {
      shortcut.callback();
    } else if (methodCall.name == VoiceControl.disconnect.name) {
      _calls.press(VoiceControl.disconnect);
    }

    return DBusMethodSuccessResponse();
  }
}
