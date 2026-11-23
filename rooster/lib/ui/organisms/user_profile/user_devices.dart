import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

/// One of a user's devices (Matrix sessions), as their profile lists it.
class UserDevice {
  const UserDevice({
    required this.deviceId,
    this.displayName,
    required this.verified,
    required this.blocked,
  });

  final String deviceId;
  final String? displayName;
  final bool verified;

  /// Gets no room keys from us: no message sent from now on reaches it.
  final bool blocked;
}

/// A user's devices as [matrix.Client] knows their keys, and blocking them.
abstract final class UserDevices {
  /// [userId]'s devices, by name then id.
  static List<UserDevice> of(matrix.Client client, String userId) {
    final keys = client.userDeviceKeys[userId]?.deviceKeys.values ?? const [];
    final devices = [
      for (final key in keys)
        if (key.deviceId case final deviceId?)
          UserDevice(
            deviceId: deviceId,
            displayName: key.deviceDisplayName,
            verified: key.verified,
            blocked: key.blocked,
          ),
    ];
    devices.sort((a, b) {
      final byName = (a.displayName ?? a.deviceId)
          .toLowerCase()
          .compareTo((b.displayName ?? b.deviceId).toLowerCase());
      return byName != 0 ? byName : a.deviceId.compareTo(b.deviceId);
    });
    return devices;
  }

  /// Blocks or unblocks [userId]'s device [deviceId] in the SDK's store.
  /// The SDK starts a new room session at the next message once a device
  /// of a room's member is blocked, and leaves blocked devices out of it.
  static Future<void> setBlocked(matrix.Client client, String userId,
      String deviceId, bool blocked) async {
    final key = client.userDeviceKeys[userId]?.deviceKeys[deviceId];
    // Gone since the list was drawn, or keys the SDK will not change.
    if (key == null) throw const UserDeviceChangeFailed();
    await key.setBlocked(blocked);
    if (key.blocked != blocked) throw const UserDeviceChangeFailed();
  }
}

/// Blocking or unblocking a device did not happen; shown as the error.
class UserDeviceChangeFailed implements Exception {
  const UserDeviceChangeFailed();

  static String get messageProfileDeviceChangeFailed => Intl.message(
      "This session could not be changed. Close the profile and try again.",
      name: "messageProfileDeviceChangeFailed",
      desc: "Error shown when blocking or unblocking one of a user's "
          "sessions (devices) on their profile did not work");

  @override
  String toString() => messageProfileDeviceChangeFailed;
}
