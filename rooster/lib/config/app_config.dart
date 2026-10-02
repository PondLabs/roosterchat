library;

import 'package:rooster/config/build_config.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class AppConfig {
  static Future<String> getDatabasePath() async {
    if (BuildConfig.WEB) {
      // The browser's IndexedDB name from before the renames.
      // It cannot be renamed, and a new one would log every web user out
      // (docs/adr/0002-rename-to-cockhouse.md).
      return "commet";
    }
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, "db");
  }

  static Future<String> getSocketPath() async {
    if (PlatformUtils.isWindows) {
      return r"\\.\pipe\com.pondlabs.rooster";
    }

    final dir = await getApplicationSupportDirectory();
    return join(dir.path, "socket");
  }

  static Future<String> getWidgetSocketPath() async {
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, "widget_rx");
  }

  static Future<String> getDriftDatabasePath() async {
    if (BuildConfig.WEB) {
      return "commet";
    }
    final dir = await getDatabasePath();
    return join(dir, "account", "drift");
  }
}
