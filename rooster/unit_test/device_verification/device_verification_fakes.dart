import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/auth.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import '../speed_log/fake_account.dart';

const ownUser = '@test:fakeServer.notExisting';
const ownDevice = 'GHTYAJCE';

/// The recovery key of the SDK's fake account
/// (`third_party/matrix-dart-sdk/test/fake_client.dart`): it opens the
/// secret storage the fake sync carries, with the cross-signing keys in it.
const recoveryKey =
    'EsT9 RzbW VhPW yqNp cC7j ViiW 5TZB LuY4 ryyv 9guN Ysmr WDPH';

/// The olm account the SDK's own tests give [ownUser] on [ownDevice]: the
/// fake server knows its keys.
const _pickledOlmAccount =
    'huxcPifHlyiQsX7cZeMMITbka3hLeUT3ss6DLL6dV7knaD4wgAYK6gcWknkixnX8C5KMIyxzytxiNqAOhDFRE5NsET8hr2dQ8OvXX7M95eQ7/3dPi7FkPUIbvneTSGgJYNDxJdHsDJ8OBHZ3BoqUJFDbTzFfVJjEzN4G9XQwPDafZ2p5WyerOK8Twj/rvk5N+ERmkt1XgVLQl66we/BO1ugTeM3YpDHm5lTzFUitJGTIuuONsKG9mmzdAmVUJ9YIrSxwmOBdegbGA+LAl5acg5VOol3KxRgZUMJQRQ58zpBAs72oauHizv1QVoQ7uIUiCUeb9lym+TEjmApvhru/1CPHU90K5jHNZ57wb/4V9VsqBWuoNibzDWG35YTFLcx0o+1lrCIjm1QjuC0777G+L1HNw5wnppV3z/k0YujjuPS3wvOA30TjHg';

/// The SDK's fake homeserver, with this device as a fresh login finds it:
/// in `keys/query` [ownDevice] carries only its own signature, unless
/// [signed]. A signature this device uploads (`keys/signatures/upload`) is
/// kept and given back from then on, as a homeserver does. Without
/// [crossSigning] the account has no master, self-signing nor user-signing
/// key.
class VerificationServer extends FakeTransport {
  VerificationServer({this.crossSigning = true, this.signed = false});

  final bool crossSigning;
  final bool signed;

  /// What this device uploaded about itself: its signatures by key id.
  Map<String, Object?>? uploaded;

  /// Every `keys/signatures/upload` body, as the server got it.
  final List<String> signatureUploads = [];

  /// While set, `keys/query` fails with a 500, as a homeserver that is
  /// down or overloaded.
  bool failKeyQueries = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/keys/signatures/upload')) {
      // The request comes wrapped by the speed log: read it, and hand the
      // fake API a copy.
      final bytes = await request.finalize().toBytes();
      final body = utf8.decode(bytes);
      signatureUploads.add(body);
      final device = (jsonDecode(body) as Map)[ownUser]?[ownDevice];
      if (device is Map) {
        uploaded = {
          ...?uploaded,
          ...(device['signatures'][ownUser] as Map).cast<String, Object?>(),
        };
      }
      request = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = bytes;
    }
    if (failKeyQueries &&
        request.method == 'POST' &&
        path.endsWith('/keys/query')) {
      return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(
              {'errcode': 'M_UNKNOWN', 'error': 'Internal server error'}))),
          500,
          headers: {'content-type': 'application/json'},
          request: request);
    }
    final response = await super.send(request);
    if (request.method != 'POST' || !path.endsWith('/keys/query')) {
      return response;
    }
    final json = jsonDecode(await response.stream.bytesToString()) as Map;
    final signatures =
        json['device_keys'][ownUser][ownDevice]['signatures'][ownUser] as Map;
    if (!signed) {
      signatures.removeWhere((key, _) => key != 'ed25519:$ownDevice');
    }
    uploaded?.forEach((key, value) => signatures[key] = value);
    if (!crossSigning) {
      for (final keys in ['master_keys', 'self_signing_keys']) {
        (json[keys] as Map?)?.remove(ownUser);
      }
      (json['user_signing_keys'] as Map?)?.remove(ownUser);
    }
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(json))), response.statusCode,
        headers: response.headers, request: request);
  }
}

/// Signs in as [ownUser] on [ownDevice] with the SDK's fake account, which
/// stands in for typing the password: the session is made, one sync runs
/// and the keys are fetched, then the sync loop stops so the test drives
/// each sync. A [verified] device was verified in an earlier run: it
/// trusts the account's master key, as after the recovery key or emoji.
class FakeLogin implements LoginFlow {
  FakeLogin({this.verified = false});

  final bool verified;

  @override
  Future<LoginResult> submit(Client client) async {
    final mx = (client as MatrixClient).getMatrixClient();
    FakeMatrixApi.client = mx;
    await mx.checkHomeserver(Uri.parse('https://fakeServer.notExisting'),
        checkWellKnown: false);
    await mx.init(
      newToken: 'abcd',
      newUserID: ownUser,
      newHomeserver: mx.homeserver,
      newDeviceName: 'Test client',
      newDeviceID: ownDevice,
      newOlmAccount: _pickledOlmAccount,
    );
    await mx.abortSync();
    mx.backgroundSync = false;
    await mx.updateUserDeviceKeys();
    if (verified) {
      await mx.userDeviceKeys[ownUser]!.masterKey!.setVerified(true, false);
    }
    return LoginResultSuccess();
  }
}

/// [dir] as the flutter_rust_bridge loader takes it: it goes through
/// `Uri.resolve`, so `C:/x` must be `/C:/x/` (a shell may drop the slash).
String _libraryDir(String dir) {
  var path = dir.replaceAll(r'\', '/');
  if (!path.startsWith('/')) path = '/$path';
  return path.endsWith('/') ? path : '$path/';
}

/// Why the encrypted tests do not run here, or false.
Object get skipWithoutVodozemac =>
    Platform.environment['VODOZEMAC_LIB_DIR'] == null
        ? 'VODOZEMAC_LIB_DIR is not set: no encryption here'
        : false;

var _accounts = 0;

/// A Rooster account on [server], not signed in yet.
Future<MatrixClient> newAccount(VerificationServer server) async {
  final dir = Platform.environment['VODOZEMAC_LIB_DIR']!;
  if (!vod.isInitialized()) await vod.init(libraryPath: _libraryDir(dir));
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
  final name = 'device_verification_${_accounts++}';
  final database = await matrix.MatrixSdkDatabase.init(
    name,
    database: await databaseFactoryFfi.openDatabase(':memory:',
        options: OpenDatabaseOptions(singleInstance: false)),
    sqfliteFactory: databaseFactoryFfi,
  );
  return MatrixClient(identifier: name, database: database, transport: server);
}

/// A sync with nothing in it: what the app checks the device on.
Future<void> emptySync(MatrixClient client, String batch) async {
  final mx = client.getMatrixClient();
  await mx.database
      .transaction(() => mx.handleSync(matrix.SyncUpdate(nextBatch: batch)));
}
