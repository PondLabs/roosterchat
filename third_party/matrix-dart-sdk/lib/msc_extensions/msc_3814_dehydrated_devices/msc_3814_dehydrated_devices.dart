/// Extensions for the experimental dehydrated devices MSC, which allows
/// receiving encrypted messages while you have no devices signed in.
library;

import 'dart:convert';
import 'dart:math';

import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/base64_unpadded.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/msc_extensions/msc_3814_dehydrated_devices/api.dart';
import 'package:matrix/msc_extensions/msc_3814_dehydrated_devices/model/dehydrated_device.dart';
import 'package:matrix/src/utils/crypto/crypto.dart' as uc;

// ROOSTER: what a run of [DehydratedDeviceHandler.dehydratedDeviceSetup]
// did, so the app can say it and a test can tell the cases apart.
enum DehydratedDeviceStatus {
  /// The opt-in is off, or there is no encryption or cross-signing: the
  /// server was not asked anything.
  disabled,

  /// The server does not announce MSC3814: no MSC3814 endpoint was called.
  unsupported,

  /// There was no dehydrated device: a new one was uploaded.
  created,

  /// The dehydrated device's to-device events were read, then a new device
  /// replaced it.
  rehydrated,

  /// The dehydrated device could not be used (an older algorithm, unknown
  /// or not cross-signed, or without its account) and a new one replaced it.
  replaced,

  /// The dehydrated device uses an algorithm we do not know: left as it is.
  unknownAlgorithm,

  /// The key in secret storage is missing or does not open the dehydrated
  /// device: left as it is, and nothing of this session changed.
  keyMismatch,

  /// The server or the network failed: nothing of this session changed.
  failed,
}

// ROOSTER: see [DehydratedDeviceStatus].
class DehydratedDeviceResult {
  const DehydratedDeviceResult(this.status, {this.roomKeys = 0});

  final DehydratedDeviceStatus status;

  /// How many room keys sent to the dehydrated device were handed to this
  /// session's key manager.
  final int roomKeys;

  /// A dehydrated device of ours is on the server now.
  bool get succeeded => const {
        DehydratedDeviceStatus.created,
        DehydratedDeviceStatus.rehydrated,
        DehydratedDeviceStatus.replaced,
      }.contains(status);

  @override
  String toString() => 'DehydratedDeviceResult($status, roomKeys: $roomKeys)';
}

extension DehydratedDeviceHandler on Client {
  static const Set<String> _oldDehydratedDeviceAlgorithms = {
    'com.famedly.dehydrated_device.raw_olm_account',
  };
  static const String _dehydratedDeviceAlgorithm =
      'com.famedly.dehydrated_device.raw_olm_account.v2';
  static const String _ssssSecretNameForDehydratedDevice = 'org.matrix.msc3814';

  // ROOSTER: the flag a server sets in `unstable_features` of
  // `/_matrix/client/versions` when it serves MSC3814. No spec version has
  // the stable endpoints yet, so this is the only signal.
  static const String unstableFeature = 'org.matrix.msc3814';

  // ROOSTER: whether the server announces MSC3814. Only `/versions` (cached
  // by [getVersions]) is asked; an error answers false.
  Future<bool> dehydratedDevicesSupported() async {
    try {
      final versions = await getVersions();
      return versions.unstableFeatures?[unstableFeature] == true;
    } catch (e) {
      Logs().w('Could not tell whether the server serves MSC3814: $e');
      return false;
    }
  }

  // ROOSTER: deletes our dehydrated device when the server serves MSC3814,
  // for turning the opt-in off. No device there is not an error. Returns
  // whether the server was asked.
  Future<bool> deleteDehydratedDeviceIfSupported() async {
    if (!await dehydratedDevicesSupported()) return false;
    try {
      await deleteDehydratedDevice();
    } on MatrixException catch (e) {
      if (e.response?.statusCode != 404 && e.error != MatrixError.M_NOT_FOUND) {
        rethrow;
      }
    }
    return true;
  }

  /// Restores the dehydrated device account and/or creates a new one, fetches the events and as such makes encrypted messages available while we were offline.
  /// Usually it only makes sense to call this when you just entered the SSSS passphrase or recovery key successfully.
  // ROOSTER: never throws, and never touches this session's own account or
  // Olm sessions: a failure leaves the login as it was ([DehydratedDeviceResult]).
  Future<DehydratedDeviceResult> dehydratedDeviceSetup(
    OpenSSSS secureStorage,
  ) async {
    const disabled = DehydratedDeviceResult(DehydratedDeviceStatus.disabled);
    const failed = DehydratedDeviceResult(DehydratedDeviceStatus.failed);
    Future<DehydratedDeviceResult> replace(
      DehydratedDeviceStatus status,
    ) async =>
        await _uploadNewDevice(secureStorage)
            ? DehydratedDeviceResult(status)
            : failed;
    try {
      // dehydrated devices need to be cross-signed
      if (!enableDehydratedDevices ||
          !encryptionEnabled ||
          this.encryption?.crossSigning.enabled != true) {
        return disabled;
      }

      // ROOSTER: a server that does not announce MSC3814 is not asked.
      if (!await dehydratedDevicesSupported()) {
        Logs().i('Dehydrated devices unsupported, skipping.');
        return const DehydratedDeviceResult(
          DehydratedDeviceStatus.unsupported,
        );
      }

      DehydratedDevice? device;
      try {
        device = await getDehydratedDevice();
      } on MatrixException catch (e) {
        // ROOSTER: only "no device" (404 M_NOT_FOUND) makes a new one.
        // Upstream also replaced the device on a 500 or any other error,
        // dropping the events waiting for it.
        if (e.response?.statusCode == 404 ||
            e.error == MatrixError.M_NOT_FOUND) {
          return await replace(DehydratedDeviceStatus.created);
        }
        Logs().w(
          'Dehydrated device unavailable (${e.response?.statusCode}), skipping.',
        );
        return failed;
      }

      // Just throw away the old device if it is using an old algoritm. In the future we could try to still use it and then migrate it, but currently that is not worth the effort
      if (_oldDehydratedDeviceAlgorithms
          .contains(device.deviceData?.tryGet<String>('algorithm'))) {
        return await replace(DehydratedDeviceStatus.replaced);
      }

      // Only handle devices we understand
      // In the future we might want to migrate to a newer format here
      if (device.deviceData?.tryGet<String>('algorithm') !=
          _dehydratedDeviceAlgorithm) {
        return const DehydratedDeviceResult(
          DehydratedDeviceStatus.unknownAlgorithm,
        );
      }

      // Verify that the device is cross-signed
      final dehydratedDeviceIdentity =
          userDeviceKeys[userID]?.deviceKeys[device.deviceId];
      if (dehydratedDeviceIdentity == null ||
          !(dehydratedDeviceIdentity.hasValidSignatureChain() ||
              // ROOSTER: or up to a master key whose private half is in
              // the secret storage just unlocked (as `selfSign` checks).
              // After a login this runs while the session is verified,
              // before its master key is marked, and upstream replaced
              // the device then, with the events waiting for it.
              (await _masterKeyInStorage(secureStorage) &&
                  dehydratedDeviceIdentity.hasValidSignatureChain(
                    verifiedByTheirMasterKey: true,
                  )))) {
        Logs().w(
          'Dehydrated device ${device.deviceId} is unknown or unverified, replacing it',
        );
        return await replace(DehydratedDeviceStatus.replaced);
      }

      final pickledDevice = device.deviceData?.tryGet<String>('device');
      if (pickledDevice == null) {
        Logs()
            .w('Dehydrated device ${device.deviceId} is invalid, replacing it');
        return await replace(DehydratedDeviceStatus.replaced);
      }

      // ROOSTER: no key in secret storage (or one this storage key cannot
      // decrypt) leaves the device and its events on the server.
      final String pickleDeviceKey;
      try {
        pickleDeviceKey =
            await secureStorage.getStored(_ssssSecretNameForDehydratedDevice);
      } catch (_) {
        Logs().w('No usable key for the dehydrated device in secret storage');
        return const DehydratedDeviceResult(
          DehydratedDeviceStatus.keyMismatch,
        );
      }

      // Use a separate encryption object for the dehydrated device.
      // We need to be careful to not use the client.deviceId here and such.
      final encryption = Encryption(client: this);
      try {
        // ROOSTER: a key that does not open the pickle is a mismatch, not
        // a reason to drop the device.
        try {
          await encryption.init(
            pickledDevice,
            deviceId: device.deviceId,
            pickleKey: pickleDeviceKey,
            dehydratedDeviceAlgorithm: _dehydratedDeviceAlgorithm,
          );
        } catch (_) {
          Logs().w(
            'The key in secret storage does not open dehydrated device ${device.deviceId}',
          );
          return const DehydratedDeviceResult(
            DehydratedDeviceStatus.keyMismatch,
          );
        }

        if (dehydratedDeviceIdentity.curve25519Key != encryption.identityKey ||
            dehydratedDeviceIdentity.ed25519Key != encryption.fingerprintKey) {
          Logs()
              .w('Invalid dehydrated device ${device.deviceId}, replacing it');
          await encryption.dispose();
          return await replace(DehydratedDeviceStatus.replaced);
        }

        // Fetch the to_device messages sent to the picked device and handle them 1:1.
        // ROOSTER: the room keys go to this session's key manager (into
        // `setInboundGroupSession`, which compares them with the stored
        // ones), so they are in memory and in the database at once; an
        // event that does not decrypt is skipped, not the whole run; and
        // a server that gives the same `next_batch` again ends the loop.
        var roomKeys = 0;
        String? nextBatch;
        while (true) {
          final events = await getDehydratedDeviceEvents(
            device.deviceId,
            nextBatch: nextBatch,
          );
          final page = events.events ?? const <ToDeviceEvent>[];

          for (final e in page) {
            // We are only interested in roomkeys, which ALWAYS need to be encrypted.
            if (e.type != EventTypes.Encrypted) continue;
            final decryptedEvent = await encryption.decryptToDeviceEvent(e);
            if (decryptedEvent.type == EventTypes.RoomKey) {
              await this.encryption!.keyManager.handleToDeviceEvent(
                    decryptedEvent,
                  );
              roomKeys++;
            }
          }
          if (page.isEmpty ||
              events.nextBatch == null ||
              events.nextBatch == nextBatch) {
            break;
          }
          nextBatch = events.nextBatch;
        }

        // make sure the sessions we just received get uploaded before we upload a new device (which deletes the old device).
        await this
            .encryption
            ?.keyManager
            .uploadInboundGroupSessions(skipIfInProgress: false);

        return await _uploadNewDevice(secureStorage)
            ? DehydratedDeviceResult(
                DehydratedDeviceStatus.rehydrated,
                roomKeys: roomKeys,
              )
            : failed;
      } finally {
        await encryption.dispose();
      }
    } catch (e) {
      Logs().w('Exception while handling dehydrated devices: ${e.toString()}');
      return failed;
    }
  }

  // ROOSTER: whether our master key, as `/keys/query` gives it, is the one
  // whose private key [storage] holds.
  Future<bool> _masterKeyInStorage(OpenSSSS storage) async {
    try {
      final private = base64decodeUnpadded(
        await storage.getStored(EventTypes.CrossSigningMasterKey),
      );
      final public = vod.PkSigning.fromSecretKey(base64Encode(private))
          .publicKey
          .toBase64();
      return userDeviceKeys[userID]?.masterKey?.ed25519Key == public;
    } catch (_) {
      return false;
    }
  }

  // ROOSTER: returns whether the new device is on the server and
  // cross-signed.
  Future<bool> _uploadNewDevice(OpenSSSS secureStorage) async {
    final encryption = Encryption(client: this);

    try {
      String? pickleDeviceKey;
      try {
        pickleDeviceKey =
            await secureStorage.getStored(_ssssSecretNameForDehydratedDevice);
      } catch (_) {
        Logs().i('Dehydrated device key not found, creating new one.');
        pickleDeviceKey = base64.encode(uc.secureRandomBytes(128));
        await secureStorage.store(
          _ssssSecretNameForDehydratedDevice,
          pickleDeviceKey,
        );
      }

      const chars =
          'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
      final rnd = Random();

      final deviceIdSuffix = String.fromCharCodes(
        Iterable.generate(
          10,
          (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
        ),
      );
      final String device = 'FAM$deviceIdSuffix';

      // Generate a new olm account for the dehydrated device.
      try {
        await encryption.init(
          null,
          deviceId: device,
          pickleKey: pickleDeviceKey,
          dehydratedDeviceAlgorithm: _dehydratedDeviceAlgorithm,
        );
      } on MatrixException catch (_) {
        // dehydrated devices unsupported, do noting.
        Logs().i('Dehydrated devices unsupported, skipping upload.');
        await encryption.dispose();
        return false;
      }

      encryption.ourDeviceId = device;
      encryption.olmManager.ourDeviceId = device;

      // cross sign the device from our currently signed in device
      await updateUserDeviceKeys(additionalUsers: {userID!});
      // ROOSTER: a server that does not list the new device yet leaves it
      // unsigned; the next run replaces it.
      final uploaded = userDeviceKeys[userID]?.deviceKeys[device];
      if (uploaded == null) {
        Logs().w('Dehydrated device $device is not listed, not signing it');
        return false;
      }
      await this.encryption?.crossSigning.sign([uploaded]);
      return true;
    } finally {
      await encryption.dispose();
    }
  }
}
