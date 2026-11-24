/// QR code login (MSC4108) on a Matrix client: the new device's
/// [LoginFlow], which signs in with the same device authorization grant
/// and token exchange as "Sign in from another device"
/// ([MatrixDeviceAuthFlow]), and the signed-in device's side.
library;

import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/auth.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/auth/matrix_device_auth_flow.dart';
import 'package:rooster/client/matrix/auth/matrix_sso_login_flow.dart';
import 'package:rooster/client/matrix/auth/qr_login/ecies.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_error.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_protocol.dart';
import 'package:rooster/client/matrix/auth/qr_login/rendezvous_channel.dart';
import 'package:rooster/client/matrix/auth/qr_login/secure_channel.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/debug/log.dart';

/// Where the new device can make its rendezvous on [mx]'s homeserver, or
/// null when the server offers none.
Future<Uri?> matrixRendezvousEndpoint(matrix.Client mx) async {
  final homeserver = mx.homeserver;
  if (homeserver == null) return null;
  Map<String, Object?>? wellKnown;
  try {
    wellKnown = (await mx.getWellknown()).additionalProperties;
  } catch (_) {
    // No discovery file: the homeserver itself, if it has the endpoint.
  }
  Map<String, bool>? features;
  try {
    features = (await mx.getVersions()).unstableFeatures;
  } catch (_) {
    features = null;
  }
  return rendezvousEndpoint(homeserver,
      wellKnown: wellKnown, unstableFeatures: features);
}

/// The new device: signs in once the person typed the check code.
class MatrixQrLoginFlow implements LoginFlow, QrLoginNewDeviceHost {
  MatrixQrLoginFlow({
    required this.channel,
    required this.typedCheckCode,
    required this.authMetadata,
    this.clock = const SystemDeviceGrantClock(),
  });

  final QrSecureChannel channel;
  final DeviceGrantClock clock;
  final int typedCheckCode;
  final matrix.GetAuthMetadataResponse authMetadata;

  final ValueNotifier<QrLoginStep> step =
      ValueNotifier(QrLoginStep.waitingForApproval);

  Client? _client;
  LoginResult? _signIn;
  MatrixDeviceAuthFlow? _grant;
  bool _cancelled = false;

  /// The person closed the panel: stops the grant and the channel.
  void cancel() {
    _cancelled = true;
    _grant?.cancel();
    unawaited(channel.close());
  }

  @override
  Future<LoginResult> submit(Client client) async {
    if (client is! MatrixClient) {
      await channel.close();
      return LoginResultError(MatrixSSOLoginFlow.errorLoginWrongClientType);
    }
    _client = client;
    try {
      await runQrLoginNewDevice(channel, this,
          typedCheckCode: typedCheckCode, onStep: (s) => step.value = s);
      return _signIn ?? LoginResultFailed();
    } on QrLoginException catch (e) {
      await channel.close();
      // Signed in already, only the keys did not come: still a new
      // device, verified the usual way.
      if (_signIn is LoginResultSuccess) {
        Log.w("QR code login: signed in without keys (${e.error.name})");
        return _signIn!;
      }
      return _cancelled
          ? LoginResultCancelled()
          : LoginResultError(e.error.message);
    } catch (e, s) {
      await channel.close();
      Log.onError(e, s, content: "QR code login failed");
      return _signIn is LoginResultSuccess
          ? _signIn!
          : LoginResultError(QrLoginError.failed.message);
    }
  }

  @override
  Future<QrLoginGrant> startGrant(Uri homeserver) async {
    final client = _client as MatrixClient;
    final ours = client.getMatrixClient().homeserver;
    if (ours == null || !_sameOrigin(ours, homeserver)) {
      throw const QrLoginException(QrLoginError.homeserverMismatch);
    }
    final grant =
        _grant = MatrixDeviceAuthFlow(authMetadata: authMetadata, clock: clock);
    final signIn = grant.submit(client).then((result) => _signIn = result);
    final prompt = Completer<DeviceAuthorizationPrompt?>();
    void listener() {
      final value = grant.prompt.value;
      if (value != null && !prompt.isCompleted) prompt.complete(value);
    }

    grant.prompt.addListener(listener);
    unawaited(signIn.whenComplete(() {
      if (!prompt.isCompleted) prompt.complete(null);
    }));
    final shown = await prompt.future;
    grant.prompt.removeListener(listener);
    if (shown == null) {
      throw QrLoginException(_signIn is LoginResultCancelled
          ? QrLoginError.cancelled
          : QrLoginError.failed);
    }
    return QrLoginGrant(
      deviceId: grant.deviceId,
      verificationUri: shown.verificationUri,
      verificationUriComplete: shown.verificationUriComplete,
      signedIn: signIn.then((result) => result is LoginResultSuccess),
      cancel: grant.cancel,
    );
  }

  @override
  Future<void> importSecrets(QrLoginSecrets secrets) => importQrLoginSecrets(
      (_client as MatrixClient).getMatrixClient(), secrets);
}

/// Same scheme, host and port (the port a scheme implies included).
bool _sameOrigin(Uri a, Uri b) =>
    a.scheme == b.scheme && a.host == b.host && a.port == b.port;

/// Keeps each of [secrets] that matches the account's published public key
/// (the others are dropped), the way a secret shared by another device is
/// kept, then cross-signs this device with them.
Future<void> importQrLoginSecrets(
    matrix.Client mx, QrLoginSecrets secrets) async {
  final encryption = mx.encryption;
  final userId = mx.userID;
  if (encryption == null || userId == null || secrets.isEmpty) return;
  await mx.updateUserDeviceKeys(additionalUsers: {userId});
  final keys = mx.userDeviceKeys[userId];

  Future<bool> keep(String type, String? secret, String? publicKey,
      Future<List<int>> Function(List<int> seed) derive) async {
    if (secret == null || publicKey == null) return false;
    try {
      final public = await derive(eciesBase64Decode(secret));
      if (eciesBase64Encode(public) != publicKey) {
        Log.w("QR code login: the $type secret does not match the account");
        return false;
      }
    } catch (_) {
      return false;
    }
    final keyId = encryption.ssss.keyIdFromType(type);
    final ciphertext = keyId == null
        ? null
        : mx.accountData[type]?.content
            .tryGetMap<String, Object?>('encrypted')
            ?.tryGetMap<String, Object?>(keyId)
            ?.tryGet<String>('ciphertext');
    if (keyId == null || ciphertext == null) return false;
    await mx.database.storeSSSSCache(type, keyId, ciphertext, secret);
    return true;
  }

  Future<List<int>> ed25519(List<int> seed) async =>
      (await (await Ed25519().newKeyPairFromSeed(seed)).extractPublicKey())
          .bytes;
  Future<List<int>> x25519(List<int> seed) async =>
      (await (await X25519().newKeyPairFromSeed(seed)).extractPublicKey())
          .bytes;

  final master = await keep(matrix.EventTypes.CrossSigningMasterKey,
      secrets.masterKey, keys?.masterKey?.ed25519Key, ed25519);
  final selfSigning = await keep(matrix.EventTypes.CrossSigningSelfSigning,
      secrets.selfSigningKey, keys?.selfSigningKey?.ed25519Key, ed25519);
  await keep(matrix.EventTypes.CrossSigningUserSigning, secrets.userSigningKey,
      keys?.userSigningKey?.ed25519Key, ed25519);

  final ownDevice = keys?.deviceKeys[mx.deviceID];
  final masterKey = keys?.masterKey;
  if (master && selfSigning && ownDevice != null && masterKey != null) {
    await masterKey.setVerified(true, false);
    await encryption.crossSigning.sign([masterKey, ownDevice]);
  }

  if (secrets.backupKey != null) {
    try {
      final info = await encryption.keyManager.getRoomKeysBackupInfo(false);
      if (info.version == secrets.backupVersion &&
          info.algorithm ==
              matrix.BackupAlgorithm.mMegolmBackupV1Curve25519AesSha2 &&
          await keep(matrix.EventTypes.MegolmBackup, secrets.backupKey,
              info.authData['public_key'] as String?, x25519)) {
        unawaited(encryption.keyManager.loadAllKeys());
      }
    } catch (e) {
      Log.w("QR code login: no key backup to restore (${e.runtimeType})");
    }
  }
}

/// The signed-in device: [approve] is called with the page where the
/// person approves the new device.
class MatrixQrLoginExistingDevice implements QrLoginExistingDeviceHost {
  MatrixQrLoginExistingDevice(this.mx, {required this.onApprove});

  final matrix.Client mx;
  final Future<void> Function(Uri verificationUri) onApprove;

  @override
  Uri get homeserver => mx.homeserver!;

  @override
  Future<void> approve(Uri verificationUri) => onApprove(verificationUri);

  /// The page's whole origin (scheme, host and port) must be one of the
  /// authorization server's: an `http:` page on the issuer's host is not
  /// the issuer's page, anyone on the network can answer it.
  @override
  Future<bool> trusts(Uri verificationUri) async {
    try {
      final metadata = await mx.getAuthMetadata();
      return [
        metadata.issuer,
        metadata.authorizationEndpoint,
        metadata.deviceAuthorizationEndpoint,
      ].any((server) => server != null && _sameOrigin(server, verificationUri));
    } catch (_) {
      // No OAuth 2.0 server: no page to trust.
      return false;
    }
  }

  @override
  Future<bool> deviceExists(String deviceId) async {
    try {
      await mx.getDevice(deviceId);
      return true;
    } on matrix.MatrixException catch (e) {
      if (e.error == matrix.MatrixError.M_NOT_FOUND) return false;
      rethrow;
    }
  }

  @override
  Future<QrLoginSecrets> exportSecrets() async {
    final ssss = mx.encryption?.ssss;
    if (ssss == null) return const QrLoginSecrets();
    final backupKey = await ssss.getCached(matrix.EventTypes.MegolmBackup);
    String? backupVersion;
    if (backupKey != null) {
      try {
        backupVersion =
            (await mx.encryption!.keyManager.getRoomKeysBackupInfo()).version;
      } catch (_) {
        backupVersion = null;
      }
    }
    return QrLoginSecrets(
      masterKey: await ssss.getCached(matrix.EventTypes.CrossSigningMasterKey),
      selfSigningKey:
          await ssss.getCached(matrix.EventTypes.CrossSigningSelfSigning),
      userSigningKey:
          await ssss.getCached(matrix.EventTypes.CrossSigningUserSigning),
      backupKey: backupVersion == null ? null : backupKey,
      backupVersion: backupVersion,
      backupAlgorithm:
          matrix.BackupAlgorithm.mMegolmBackupV1Curve25519AesSha2.name,
    );
  }
}
