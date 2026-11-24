/// The MSC4108 sign-in over an established [QrSecureChannel], with the new
/// device signing in through the OAuth 2.0 device authorization grant:
///
/// | signed-in device (S) | | new device (G) |
/// |---|---|---|
/// | `m.login.protocols` (grant, homeserver) | → | |
/// | | ← | `m.login.protocol` (verification URL, device ID) |
/// | opens the URL to approve; `m.login.protocol_accepted` | → | polls the token endpoint |
/// | | ← | `m.login.success` |
/// | checks the device is on the account; `m.login.secrets` | → | checks and keeps the keys |
///
/// Either side may answer `m.login.failure` (or `m.login.declined`), which
/// ends it. The secrets are the cross-signing private keys and the key
/// backup's key, never logged or printed.
library;

import 'dart:async';

import 'package:rooster/client/matrix/auth/qr_login/qr_login_error.dart';
import 'package:rooster/client/matrix/auth/qr_login/secure_channel.dart';

const qrLoginDeviceGrant = 'device_authorization_grant';

/// The `m.login.secrets` content. [toString] shows which are there, never
/// their values.
class QrLoginSecrets {
  const QrLoginSecrets({
    this.masterKey,
    this.selfSigningKey,
    this.userSigningKey,
    this.backupKey,
    this.backupVersion,
    this.backupAlgorithm,
  });

  final String? masterKey;
  final String? selfSigningKey;
  final String? userSigningKey;
  final String? backupKey;
  final String? backupVersion;
  final String? backupAlgorithm;

  bool get isEmpty =>
      masterKey == null &&
      selfSigningKey == null &&
      userSigningKey == null &&
      backupKey == null;

  Map<String, Object?> toMessage() => {
        'type': 'm.login.secrets',
        if (masterKey != null ||
            selfSigningKey != null ||
            userSigningKey != null)
          'cross_signing': {
            if (masterKey != null) 'master_key': masterKey,
            if (selfSigningKey != null) 'self_signing_key': selfSigningKey,
            if (userSigningKey != null) 'user_signing_key': userSigningKey,
          },
        if (backupKey != null && backupVersion != null)
          'backup': {
            'algorithm': backupAlgorithm,
            'key': backupKey,
            'backup_version': backupVersion,
          },
      };

  static QrLoginSecrets fromMessage(Map<String, Object?> message) {
    String? read(Object? map, String key) =>
        map is Map && map[key] is String ? map[key] as String : null;
    final crossSigning = message['cross_signing'];
    final backup = message['backup'];
    return QrLoginSecrets(
      masterKey: read(crossSigning, 'master_key'),
      selfSigningKey: read(crossSigning, 'self_signing_key'),
      userSigningKey: read(crossSigning, 'user_signing_key'),
      backupKey: read(backup, 'key'),
      backupVersion: read(backup, 'backup_version'),
      backupAlgorithm: read(backup, 'algorithm'),
    );
  }

  @override
  String toString() => 'QrLoginSecrets('
      'crossSigning: ${masterKey != null}/${selfSigningKey != null}/'
      '${userSigningKey != null}, backup: ${backupKey != null})';
}

/// A device authorization grant the new device started: what the signed-in
/// device opens, and the sign-in that completes when it is approved.
class QrLoginGrant {
  QrLoginGrant({
    required this.deviceId,
    required this.verificationUri,
    this.verificationUriComplete,
    required this.signedIn,
    required this.cancel,
  });

  final String deviceId;
  final Uri verificationUri;
  final Uri? verificationUriComplete;

  /// True once the new device holds its tokens.
  final Future<bool> signedIn;
  final void Function() cancel;
}

/// What the new device's side needs from Matrix.
abstract class QrLoginNewDeviceHost {
  /// Starts the grant on [homeserver] (from `m.login.protocols`). Throws
  /// [QrLoginException] when it cannot, such as another homeserver than
  /// the one the person chose.
  Future<QrLoginGrant> startGrant(Uri homeserver);

  /// Checks [secrets] against the account's public keys and keeps the ones
  /// that match.
  Future<void> importSecrets(QrLoginSecrets secrets);
}

enum QrLoginStep {
  connecting,
  confirmCheckCode,
  waitingForApproval,
  approve,
  signingIn,
  sharingKeys,
  done,
}

/// The new device's side, from the check code the person typed on.
/// Returns once signed in, with the secrets applied.
Future<void> runQrLoginNewDevice(
  QrSecureChannel channel,
  QrLoginNewDeviceHost host, {
  required int typedCheckCode,
  void Function(QrLoginStep step)? onStep,
}) async {
  if (typedCheckCode != channel.checkCode.digits) {
    await channel.fail('user_cancelled');
    throw const QrLoginException(QrLoginError.checkCodeMismatch);
  }
  onStep?.call(QrLoginStep.waitingForApproval);
  final protocols = await channel.receive({'m.login.protocols'});
  final homeserver = protocols['homeserver'];
  final offered = protocols['protocols'];
  final homeserverUri = homeserver is String ? Uri.tryParse(homeserver) : null;
  if (offered is! List ||
      !offered.contains(qrLoginDeviceGrant) ||
      homeserverUri == null ||
      !homeserverUri.isScheme('https') && !homeserverUri.isScheme('http')) {
    await channel.fail('unsupported_protocol');
    throw const QrLoginException(QrLoginError.unsupported);
  }

  final QrLoginGrant grant;
  try {
    grant = await host.startGrant(homeserverUri);
  } on QrLoginException {
    await channel.fail('unsupported_protocol');
    rethrow;
  } catch (_) {
    await channel.fail('unsupported_protocol');
    throw const QrLoginException(QrLoginError.failed);
  }
  try {
    await channel.send({
      'type': 'm.login.protocol',
      'protocol': qrLoginDeviceGrant,
      'device_authorization_grant': {
        'verification_uri': grant.verificationUri.toString(),
        if (grant.verificationUriComplete != null)
          'verification_uri_complete': grant.verificationUriComplete.toString(),
      },
      'device_id': grant.deviceId,
    });
    await channel.receive({'m.login.protocol_accepted'});
  } catch (_) {
    grant.cancel();
    rethrow;
  }
  onStep?.call(QrLoginStep.signingIn);
  if (!await grant.signedIn) {
    await channel.fail('authorization_expired');
    throw const QrLoginException(QrLoginError.notApproved);
  }
  await channel.send({'type': 'm.login.success'});
  onStep?.call(QrLoginStep.sharingKeys);
  final secrets = await channel.receive({'m.login.secrets'});
  await channel.close();
  await host.importSecrets(QrLoginSecrets.fromMessage(secrets));
  onStep?.call(QrLoginStep.done);
}

/// What the signed-in device's side needs from Matrix.
abstract class QrLoginExistingDeviceHost {
  Uri get homeserver;

  Future<bool> deviceExists(String deviceId);

  /// The page where the person approves the new device; awaited until it
  /// was opened (or offered to open).
  Future<void> approve(Uri verificationUri);

  Future<QrLoginSecrets> exportSecrets();
}

/// The signed-in device's side, right after [QrSecureChannel.connect].
/// [checkDevice] waits between looks for the new device on the account.
Future<QrLoginSecrets> runQrLoginExistingDevice(
  QrSecureChannel channel,
  QrLoginExistingDeviceHost host, {
  void Function(QrLoginStep step)? onStep,
  Duration deviceWait = const Duration(seconds: 2),
  int deviceChecks = 10,
  Future<void> Function(Duration delay) sleep = _sleep,
}) async {
  onStep?.call(QrLoginStep.confirmCheckCode);
  await channel.send({
    'type': 'm.login.protocols',
    'protocols': [qrLoginDeviceGrant],
    'homeserver': host.homeserver.toString(),
  });
  // The person types the check code on the new device meanwhile: it
  // answers only once they did.
  final protocol =
      await channel.receive({'m.login.protocol'}, timeout: _personTimeout);
  final grant = protocol['device_authorization_grant'];
  final deviceId = protocol['device_id'];
  final uri =
      _webUri(grant is Map ? grant['verification_uri_complete'] : null) ??
          _webUri(grant is Map ? grant['verification_uri'] : null);
  if (protocol['protocol'] != qrLoginDeviceGrant ||
      deviceId is! String ||
      deviceId.isEmpty ||
      uri == null) {
    await channel.fail('unsupported_protocol');
    throw const QrLoginException(QrLoginError.unsupported);
  }
  if (await host.deviceExists(deviceId)) {
    await channel.fail('device_already_exists');
    throw const QrLoginException(QrLoginError.deviceAlreadyExists);
  }
  await channel.send({'type': 'm.login.protocol_accepted'});
  onStep?.call(QrLoginStep.approve);
  await host.approve(uri);
  await channel.receive({'m.login.success'}, timeout: _personTimeout);
  onStep?.call(QrLoginStep.sharingKeys);
  var found = false;
  for (var i = 0; i < deviceChecks && !found; i++) {
    found = await host.deviceExists(deviceId);
    if (!found) await sleep(deviceWait);
  }
  if (!found) {
    await channel.fail('device_not_found');
    throw const QrLoginException(QrLoginError.deviceNotFound);
  }
  final secrets = await host.exportSecrets();
  await channel.send(secrets.toMessage());
  onStep?.call(QrLoginStep.done);
  return secrets;
}

/// Time for a person to read, type or approve.
const _personTimeout = Duration(minutes: 10);

Future<void> _sleep(Duration delay) => Future.delayed(delay);

Uri? _webUri(Object? value) {
  final uri = value is String ? Uri.tryParse(value) : null;
  return uri != null &&
          (uri.isScheme('https') || uri.isScheme('http')) &&
          uri.host.isNotEmpty
      ? uri
      : null;
}
