import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/auth/oidc_redirect_receiver.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

const homeserverHost = 'matrix.example.org';
const authorizationEndpoint = 'https://auth.example.org/authorize';
const tokenEndpoint = 'https://auth.example.org/oauth2/token';
const registrationEndpoint = 'https://auth.example.org/oauth2/registration';

Map<String, Object?> authMetadataJson({
  List<String>? prompts,
  bool? cimd,
  List<String>? scopes,
}) =>
    {
      'issuer': 'https://auth.example.org/',
      'authorization_endpoint': authorizationEndpoint,
      'token_endpoint': tokenEndpoint,
      'registration_endpoint': registrationEndpoint,
      'response_types_supported': ['code'],
      'response_modes_supported': ['query', 'fragment'],
      'grant_types_supported': ['authorization_code', 'refresh_token'],
      'code_challenge_methods_supported': ['S256'],
      if (prompts != null) 'prompt_values_supported': prompts,
      if (cimd != null) 'client_id_metadata_document_supported': cimd,
      if (scopes != null) 'scopes_supported': scopes,
    };

/// Widget tests' binding answers every HttpClient call with 400; the
/// loopback tests need the real client to act as the browser.
class RealHttpOverrides extends HttpOverrides {}

/// A homeserver on OAuth only (MAS): `/v3/login` answers 404, the OAuth
/// endpoints answer, and the rest (whoami, sync, keys) is the SDK's
/// [FakeMatrixApi]. Every request it sees is kept in [requests].
class OAuthOnlyServer extends http.BaseClient {
  OAuthOnlyServer({this.metadata, this.loginAnswer});

  Map<String, Object?>? metadata;
  http.Response? loginAnswer;
  final FakeMatrixApi _api = FakeMatrixApi();
  final List<http.Request> requests = [];

  Iterable<http.Request> get tokenRequests =>
      requests.where((r) => r.url.toString() == tokenEndpoint);

  Iterable<http.Request> get registrationRequests =>
      requests.where((r) => r.url.toString() == registrationEndpoint);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = body;
    requests.add(copy);
    final answer = _answer(copy);
    if (answer != null) {
      return http.StreamedResponse(
        Stream.value(answer.bodyBytes),
        answer.statusCode,
        headers: answer.headers,
        request: request,
      );
    }
    // The fake server only answers its own origin.
    final forwarded = http.Request(
        request.method, copy.url.replace(host: 'fakeserver.notexisting'))
      ..headers.addAll(request.headers)
      ..bodyBytes = body;
    return _api.send(forwarded);
  }

  http.Response? _answer(http.Request request) {
    final url = request.url;
    if (url.toString() == registrationEndpoint) {
      return _json({'client_id': 'dcr-client-01', ...jsonDecode(request.body)},
          status: 201);
    }
    if (url.toString() == tokenEndpoint) {
      return _json({
        'access_token': 'at-${request.bodyFields['code']}',
        'token_type': 'Bearer',
        'expires_in': 300,
        'refresh_token': 'rt',
      });
    }
    if (url.host != homeserverHost) return null;
    switch (url.path) {
      case '/.well-known/matrix/client':
        return http.Response('', 404);
      case '/_matrix/client/versions':
        return _json({
          'versions': ['v1.11', 'v1.15'],
        });
      case '/_matrix/client/v1/auth_metadata':
        final metadata = this.metadata;
        return metadata == null
            ? _json({'errcode': 'M_UNRECOGNIZED', 'error': 'no'}, status: 404)
            : _json(metadata);
      case '/_matrix/client/v3/login':
        if (request.method == 'GET') {
          return loginAnswer ?? http.Response('<html>Not found</html>', 404);
        }
    }
    return null;
  }

  static http.Response _json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});
}

/// A redirect receiver that does not open a browser: [answer] builds the
/// redirect from the authorization URL the flow opened.
class FakeRedirectReceiver implements OidcRedirectReceiver {
  FakeRedirectReceiver(this.answer);

  final Uri? Function(Uri authorizationUri) answer;
  final List<Uri> opened = [];
  bool closed = false;

  @override
  final Uri redirectUri = Uri.parse('http://127.0.0.1:43123/callback');

  @override
  Future<Uri?> authorize(Uri authorizationUri) async {
    opened.add(authorizationUri);
    return answer(authorizationUri);
  }

  @override
  Future<void> close() async => closed = true;
}

/// [redirect] with [params] in its query.
Uri redirectWith(Uri redirect, Map<String, String> params) =>
    redirect.replace(queryParameters: params);

Object get skipWithoutVodozemac =>
    Platform.environment['VODOZEMAC_LIB_DIR'] == null
        ? 'VODOZEMAC_LIB_DIR is not set: PKCE hashes with vodozemac'
        : false;

/// Loads vodozemac from `VODOZEMAC_LIB_DIR` (read from [environment], the
/// process's by default). Without it this does nothing, so a `setUpAll` can
/// call it in a file whose tests are skipped by [skipWithoutVodozemac].
Future<void> initVodozemac({Map<String, String>? environment}) async {
  final dir = (environment ?? Platform.environment)['VODOZEMAC_LIB_DIR'];
  if (dir == null || vod.isInitialized()) return;
  var path = dir.replaceAll(r'\', '/');
  if (!path.startsWith('/')) path = '/$path';
  if (!path.endsWith('/')) path = '$path/';
  await vod.init(libraryPath: path);
}

var _accounts = 0;
var _preferencesReady = false;

/// A Rooster account on [server], not signed in.
Future<MatrixClient> newAccount(http.Client server) async {
  // The account's components listen to the app lifecycle and plugins.
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!_preferencesReady) {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    _preferencesReady = true;
  }
  final name = 'matrix_auth_oidc_${_accounts++}';
  final database = await matrix.MatrixSdkDatabase.init(
    name,
    database: await databaseFactoryFfi.openDatabase(':memory:',
        options: OpenDatabaseOptions(singleInstance: false)),
    sqfliteFactory: databaseFactoryFfi,
  );
  final client =
      MatrixClient(identifier: name, database: database, transport: server);
  FakeMatrixApi.client = client.getMatrixClient();
  return client;
}
