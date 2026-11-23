import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/msc_extensions/msc_3814_dehydrated_devices/msc_3814_dehydrated_devices.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';

/// What the settings panel asks of the account, so a test can stand in.
abstract class DehydratedDeviceController {
  /// Whether the server announces MSC3814 (`org.matrix.msc3814`).
  Future<bool> supported();

  /// Whether the account opted in.
  bool get enabled;

  /// Opts in: unlocks the secret storage with [recoveryKeyOrPassphrase]
  /// (which throws on a wrong one), then makes or reads the dehydrated
  /// device. The opt-in is kept only when that succeeded.
  Future<DehydratedDeviceResult> enable(String recoveryKeyOrPassphrase);

  /// Opts out and deletes the dehydrated device from the server.
  Future<void> disable();
}

/// MSC3814 dehydrated devices, opt-in per account: a stand-in device on
/// the server, its key in the secret storage, receives room keys while no
/// session of ours is signed in, and the next session that unlocks the
/// secret storage (verifying itself with the recovery key after a login)
/// reads them. The opt-in is the account data [optInType], so every
/// session of the account follows it; without it the SDK never dehydrates
/// and a login is as before.
class MatrixDehydratedDevicesComponent
    implements
        Component<MatrixClient>,
        NeedsPostLoginInit,
        DehydratedDeviceController {
  MatrixDehydratedDevicesComponent(this.client) {
    _apply();
    // Another session opting in or out reaches this one by sync.
    _mx.onSync.stream
        .where((update) =>
            update.accountData?.any((e) => e.type == optInType) == true)
        .listen((_) => _apply());
  }

  // Not translated: a Matrix account data type.
  static const String optInType = "chat.commet.dehydrated_device";

  @override
  final MatrixClient client;

  matrix.Client get _mx => client.getMatrixClient();

  @override
  bool get enabled => _mx.accountData[optInType]?.content["enabled"] == true;

  /// The SDK dehydrates (when the secret storage is unlocked) only for an
  /// account that opted in.
  void _apply() => _mx.enableDehydratedDevices = enabled;

  @override
  void postLoginInit() => _apply();

  @override
  Future<bool> supported() => _mx.dehydratedDevicesSupported();

  @override
  Future<DehydratedDeviceResult> enable(String recoveryKeyOrPassphrase) async {
    if (!await supported()) {
      return const DehydratedDeviceResult(DehydratedDeviceStatus.unsupported);
    }
    final storage = _mx.encryption!.ssss.open();
    await storage.unlock(keyOrPassphrase: recoveryKeyOrPassphrase);
    await storage.maybeCacheAll();

    _mx.enableDehydratedDevices = true;
    final result = await _mx.dehydratedDeviceSetup(storage);
    if (!result.succeeded) {
      _apply();
      return result;
    }
    await _setOptIn(true);
    return result;
  }

  @override
  Future<void> disable() async {
    await _setOptIn(false);
    await _mx.deleteDehydratedDeviceIfSupported();
  }

  Future<void> _setOptIn(bool enabled) async {
    final content = {"enabled": enabled};
    await _mx.setAccountData(_mx.userID!, optInType, content);
    // What sync will bring back, so the panel and the SDK follow now.
    _mx.accountData[optInType] =
        matrix.BasicEvent(type: optInType, content: content);
    _apply();
  }
}
