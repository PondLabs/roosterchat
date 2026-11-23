import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/matrix_client.dart';

import '../speed_log/fake_account.dart';

/// The SDK's fake homeserver, keeping every `PUT` (path and JSON body) and
/// answering a lookup of one event with `M_NOT_FOUND`, as for an event the
/// fake server never stored.
class RecordingTransport extends FakeTransport {
  final List<({String path, Object? body})> puts = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = Uri.decodeFull(request.url.path);
    if (request.method == 'GET' && path.contains('/event/')) {
      return http.StreamedResponse(
          Stream.value(utf8.encode(
              jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'Not found'}))),
          404,
          headers: {'content-type': 'application/json'});
    }
    if (request.method == 'PUT') {
      final bytes = await request.finalize().toBytes();
      puts.add((
        path: path,
        body: bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes)),
      ));
      return super.send(http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = bytes);
    }
    return super.send(request);
  }

  /// The bodies of the `PUT`s whose path ends with [suffix].
  List<Object?> putsTo(String suffix) => [
        for (final put in puts)
          if (put.path.endsWith(suffix)) put.body
      ];
}

var _eventCounter = 0;

/// Delivers [state] events to [roomId] and [accountData] as a sync would.
Future<void> syncIn(
  MatrixClient client, {
  String roomId = '!1234:fakeServer.notExisting',
  List<({String type, String stateKey, Map<String, Object?> content})> state =
      const [],
  Map<String, Map<String, Object?>> accountData = const {},
}) async {
  final mx = client.getMatrixClient();
  await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
        nextBatch: 'b${_eventCounter++}',
        accountData: [
          for (final e in accountData.entries)
            matrix.BasicEvent(type: e.key, content: e.value),
        ],
        rooms: state.isEmpty
            ? null
            : matrix.RoomsUpdate(join: {
                roomId: matrix.JoinedRoomUpdate(state: [
                  for (final s in state)
                    matrix.MatrixEvent(
                      type: s.type,
                      stateKey: s.stateKey,
                      senderId: mx.userID!,
                      eventId: '\$state${_eventCounter++}',
                      originServerTs: DateTime.now(),
                      content: s.content,
                    ),
                ]),
              }),
      )));
  await Future<void>.delayed(Duration.zero);
}

/// A pack's content with one image per shortcode in [images].
Map<String, Object?> pack(String name, Map<String, String> images) => {
      'pack': {'display_name': name},
      'images': {
        for (final e in images.entries) e.key: {'url': e.value},
      },
    };
