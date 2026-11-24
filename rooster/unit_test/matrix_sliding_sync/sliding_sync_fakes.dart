import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rooster/client/matrix/matrix_client.dart';

import '../matrix_auth_oidc/oidc_fakes.dart';

const homeserver = 'hs.example.test';
const userId = '@alice:$homeserver';
const slidingSyncPath =
    '/_matrix/client/unstable/org.matrix.simplified_msc3575/sync';

/// A homeserver that offers Simplified Sliding Sync (MSC4186) until
/// [slidingSyncGone], and `/v3/sync`.
class SlidingSyncServer extends http.BaseClient {
  bool announce = true;
  bool slidingSyncGone = false;
  final List<http.Request> requests = [];
  var _pos = 0;

  Iterable<http.Request> get slidingSyncRequests =>
      requests.where((r) => r.url.path == slidingSyncPath);
  Iterable<http.Request> get v3SyncRequests =>
      requests.where((r) => r.url.path == '/_matrix/client/v3/sync');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = body;
    requests.add(copy);
    final answer = _answer(copy);
    return http.StreamedResponse(
        Stream.value(answer.bodyBytes), answer.statusCode,
        headers: answer.headers, request: request);
  }

  http.Response _answer(http.Request request) {
    switch (request.url.path) {
      case '/_matrix/client/versions':
        return json({
          'versions': ['v1.11'],
          'unstable_features': {
            if (announce) 'org.matrix.simplified_msc3575': true,
          },
        });
      case slidingSyncPath:
        if (slidingSyncGone) {
          return json({'errcode': 'M_UNRECOGNIZED', 'error': 'gone'},
              status: 404);
        }
        return json({
          'pos': 'p${++_pos}',
          'lists': {
            'all_rooms': {'count': 0},
          },
          'rooms': {},
          'extensions': {
            'to_device': {'next_batch': '0', 'events': []},
          },
        });
      case '/_matrix/client/v3/sync':
        return json({'next_batch': 's${request.url.queryParameters.length}'});
    }
    if (request.url.path.endsWith('/filter')) {
      return json({'filter_id': 'filter-1'});
    }
    return json({});
  }

  static http.Response json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});
}

/// A Rooster account signed in on [server], before its first sync.
Future<MatrixClient> signedIn(SlidingSyncServer server) async {
  final client = await newAccount(server);
  final mx = client.getMatrixClient();
  mx.backgroundSync = false;
  mx.syncErrorTimeoutSec = 0;
  await mx.init(
    newToken: 'access-token',
    newHomeserver: Uri.https(homeserver),
    newUserID: userId,
    newDeviceID: 'DEVICE1',
    newDeviceName: 'Rooster',
    waitForFirstSync: false,
  );
  await mx.abortSync();
  return client;
}
