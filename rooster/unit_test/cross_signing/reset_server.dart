import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/encryption/ssss.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:vodozemac/vodozemac.dart' as vod;

import '../device_verification/device_verification_fakes.dart';

/// How the homeserver lets the app replace the account's verification
/// (cross-signing) keys.
enum ResetKind {
  /// The Matrix Authentication Service, as matrix.org: the person approves
  /// the reset on the account page, then the app sends the keys again.
  accountService,

  /// A server without it: the account's password, through the client API.
  password,
}

/// matrix.org's account page, on the reset.
const resetPage =
    'https://account.matrix.org/?action=org.matrix.cross_signing_reset';
const resetSession = 'reset-session';
const accountPassword = '1234';

const secretTypes = [
  'm.cross_signing.master',
  'm.cross_signing.self_signing',
  'm.cross_signing.user_signing',
];
const backupType = 'm.megolm_backup.v1';

/// The SDK's fake homeserver with what it holds for the account: its
/// account data and its published keys, from the first sync on and with
/// every write the app makes. `POST /keys/device_signing/upload` answers
/// as a [kind] server does: on matrix.org a 401 with the `m.oauth` and
/// `org.matrix.cross_signing_reset` steps until the person [approved] the
/// reset on the account page.
class ResetServer extends VerificationServer {
  ResetServer(this.kind, {this.url = resetPage}) : super(signed: true);

  final ResetKind kind;

  /// The account page the server sends the person to.
  final String url;

  /// The person approved the reset on the account page.
  bool approved = false;

  /// What the server holds in account data, by type.
  final Map<String, Map<String, Object?>> accountData = {};

  /// The cross-signing keys the server publishes, by usage.
  final Map<String, Map<String, Object?>> published = {};

  /// The public key of the newest backup version the app made.
  String? backupKey;

  /// Every `device_signing/upload`: the `auth` it carried, and whether the
  /// server took it.
  final List<(Map<String, Object?>?, bool)> uploads = [];

  /// Every write the server took, in order, as its method and what it
  /// writes (`PUT m.secret_storage.default_key`).
  final List<String> writes = [];

  /// When set, the write with this number (from 0, in the order the app
  /// sends them) fails with a 500 and is not kept: the app is interrupted
  /// there.
  int? failWrite;
  int _attempts = 0;

  /// Starts from what [client] got in its first sync, as the server
  /// holds it.
  void remember(matrix.Client client) {
    for (final MapEntry(:key, :value) in client.accountData.entries) {
      accountData[key] = jsonDecode(jsonEncode(value.content));
    }
    for (final key
        in client.userDeviceKeys[client.userID]!.crossSigningKeys.values) {
      published[key.usage.first] = key.toJson();
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final write = _write(request.method, path);
    if (write == null) return super.send(request);
    final bytes = await request.finalize().toBytes();
    final body = bytes.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    request = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bytes;

    if (path.endsWith('/keys/device_signing/upload')) {
      final auth = (body['auth'] as Map?)?.cast<String, Object?>();
      final refusal = _refusal(auth);
      uploads.add((auth, refusal == null));
      if (refusal != null) return _json(request, 401, refusal);
    }
    if (_attempts++ == failWrite) {
      return _json(
          request, 500, {'errcode': 'M_UNKNOWN', 'error': 'Interrupted'});
    }
    writes.add(write);
    if (path.endsWith('/keys/device_signing/upload')) {
      for (final usage in ['master', 'self_signing', 'user_signing']) {
        final key = body['${usage}_key'];
        if (key is Map) published[usage] = key.cast<String, Object?>();
      }
    } else if (path.contains('/account_data/')) {
      accountData[Uri.decodeComponent(path.split('/').last)] = body;
    } else if (request.method == 'POST' &&
        path.endsWith('/room_keys/version')) {
      backupKey = (body['auth_data'] as Map)['public_key'] as String;
    }
    return super.send(request);
  }

  /// What the app writes with [method] on [path], or null when it only
  /// reads.
  String? _write(String method, String path) {
    if (path.contains('/rooms/')) return null;
    if (method == 'PUT' && path.contains('/account_data/')) {
      return 'PUT ${Uri.decodeComponent(path.split('/').last)}';
    }
    if (method == 'POST' && path.endsWith('/keys/device_signing/upload')) {
      return 'POST device_signing/upload';
    }
    if (method == 'POST' && path.endsWith('/keys/signatures/upload')) {
      return 'POST signatures/upload';
    }
    if (method != 'GET' && path.contains('/room_keys/')) {
      return '$method room_keys';
    }
    return null;
  }

  /// The 401 the upload gets with [auth], or null when the server takes it.
  Map<String, Object?>? _refusal(Map<String, Object?>? auth) {
    switch (kind) {
      case ResetKind.accountService:
        // Synapse with the Matrix Authentication Service: the reset was
        // approved on the account page, whatever the request carries.
        if (approved) return null;
        return {
          'session': resetSession,
          'flows': [
            {
              'stages': ['m.oauth']
            },
            {
              'stages': ['org.matrix.cross_signing_reset']
            },
          ],
          'params': {
            'm.oauth': {'url': url},
            'org.matrix.cross_signing_reset': {'url': url},
          },
          'msg': 'To reset your end-to-end encryption cross-signing '
              'identity, you first need to approve it at $url and then try '
              'again.',
        };
      case ResetKind.password:
        if (auth?['type'] == 'm.login.password' &&
            auth?['password'] == accountPassword) {
          return null;
        }
        return {
          'session': resetSession,
          'flows': [
            {
              'stages': ['m.login.password']
            },
          ],
          'params': {},
        };
    }
  }

  http.StreamedResponse _json(
          http.BaseRequest request, int status, Object body) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          headers: {'content-type': 'application/json'}, request: request);

  /// The id of the key the account's recovery key opens.
  String? get defaultKey =>
      accountData['m.secret_storage.default_key']?['key'] as String?;

  /// What a new session finds with only [recoveryKey] and what this server
  /// holds: the private part of each secret of [types] the default key
  /// opens, by type. Fails when the recovery key is not the default key's
  /// or a secret is not in it.
  Future<Map<String, String>> openWith(String recoveryKey,
      {List<String> types = secretTypes}) async {
    final keyId = defaultKey;
    expect(keyId, isNotNull, reason: 'no default key');
    final description = accountData['m.secret_storage.key.$keyId'];
    expect(description?['algorithm'], 'm.secret_storage.v1.aes-hmac-sha2',
        reason: 'the default key has no description');
    final key = SSSS.decodeRecoveryKey(recoveryKey);
    final check =
        await SSSS.encryptAes(zeroStr, key, '', description!['iv'] as String);
    expect(_unpad(check.mac), _unpad(description['mac'] as String),
        reason: 'the recovery key does not open the default key');
    final secrets = <String, String>{};
    for (final type in types) {
      final encrypted = (accountData[type]?['encrypted'] as Map?)?[keyId];
      expect(encrypted, isA<Map>(), reason: '$type is not in the default key');
      secrets[type] = await SSSS.decryptAes(
          EncryptedContent(
              iv: encrypted['iv'] as String,
              ciphertext: encrypted['ciphertext'] as String,
              mac: encrypted['mac'] as String),
          key,
          type);
    }
    return secrets;
  }

  /// A new session verifies itself with only [recoveryKey]: the default key
  /// opens with it, and each cross-signing secret in it is the private half
  /// of the key the server publishes (and the backup's, when [backup]).
  Future<void> expectNewSessionVerifies(String recoveryKey,
      {bool backup = false}) async {
    final secrets = await openWith(recoveryKey,
        types: [...secretTypes, if (backup) backupType]);
    for (final usage in ['master', 'self_signing', 'user_signing']) {
      final public =
          vod.PkSigning.fromSecretKey(secrets['m.cross_signing.$usage']!)
              .publicKey
              .toBase64();
      final keys = (published[usage]!['keys'] as Map).values;
      expect(keys, contains(public),
          reason: 'the stored $usage key is not the published one');
    }
    if (backup) {
      final private = base64.decode(secrets[backupType]!);
      final public = vod.PkDecryption.fromSecretKey(
              vod.Curve25519PublicKey.fromBytes(Uint8List.fromList(private)))
          .publicKey;
      expect(public, backupKey,
          reason: 'the stored backup key is not the '
              "backup's");
    }
  }

  String _unpad(String s) => s.replaceAll(RegExp(r'=+$'), '');
}
