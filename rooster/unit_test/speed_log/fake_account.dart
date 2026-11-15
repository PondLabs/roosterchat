import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/diagnostic/speed_log/route_template.dart';
import 'package:rooster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The transport under the speed log's client in these tests: the SDK's
/// [FakeMatrixApi], with the next [throttleSends] `PUT /send` answered by a
/// 429 carrying [retryAfterMs]. Every request it sees is kept in [seen] as
/// its method and route template.
class FakeTransport extends http.BaseClient {
  final FakeMatrixApi _api = FakeMatrixApi();
  final List<String> seen = [];
  int throttleSends = 0;
  int retryAfterMs = 20;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    seen.add('${request.method} ${routeTemplate(request.url)}');
    if (request.method == 'PUT' &&
        request.url.path.contains('/send/') &&
        throttleSends > 0) {
      throttleSends--;
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'errcode': 'M_LIMIT_EXCEEDED',
          'error': 'Too many requests',
          'retry_after_ms': retryAfterMs,
        }))),
        429,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    return _api.send(request);
  }
}

var _preferencesReady = false;

/// A logged-in Rooster account on [transport], before its first sync.
Future<MatrixClient> fakeAccount(String name, FakeTransport transport) async {
  if (!_preferencesReady) {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    _preferencesReady = true;
  }
  final database = await matrix.MatrixSdkDatabase.init(
    name,
    database: await databaseFactoryFfi.openDatabase(':memory:',
        options: OpenDatabaseOptions(singleInstance: false)),
    sqfliteFactory: databaseFactoryFfi,
  );
  final client =
      MatrixClient(identifier: name, database: database, transport: transport);
  final mx = client.getMatrixClient();
  FakeMatrixApi.client = mx;
  await mx.checkHomeserver(Uri.parse('https://fakeServer.notExisting'),
      checkWellKnown: false);
  await mx.login(
    matrix.LoginType.mLoginPassword,
    identifier: matrix.AuthenticationUserIdentifier(user: 'test'),
    password: '1234',
  );
  return client;
}

/// A room [client] has joined, with no encryption state: the fake sync's
/// own room says it is encrypted.
Future<MatrixRoom> plainRoom(MatrixClient client) async {
  // The fake server answers every send to this room.
  const id = '!1234:fakeServer.notExisting';
  final mx = client.getMatrixClient();
  await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
        nextBatch: 'plain',
        rooms: matrix.RoomsUpdate(join: {
          id: matrix.JoinedRoomUpdate(state: [
            matrix.MatrixEvent(
              type: matrix.EventTypes.RoomMember,
              stateKey: mx.userID,
              senderId: mx.userID!,
              eventId: '\$join',
              originServerTs: DateTime.now(),
              content: {'membership': 'join'},
            ),
          ]),
        }),
      )));
  // The Rooster client adds the room on the SDK's onSync event.
  await Future<void>.delayed(Duration.zero);
  return client.getRoom(id)! as MatrixRoom;
}
