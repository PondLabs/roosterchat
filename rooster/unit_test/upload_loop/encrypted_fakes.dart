import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'loop_fakes.dart';

/// The olm account the SDK's own tests give `@test:fakeServer.notExisting`
/// (`third_party/matrix-dart-sdk/test/fake_client.dart`): the fake server
/// knows its keys.
const _pickledOlmAccount =
    'huxcPifHlyiQsX7cZeMMITbka3hLeUT3ss6DLL6dV7knaD4wgAYK6gcWknkixnX8C5KMIyxzytxiNqAOhDFRE5NsET8hr2dQ8OvXX7M95eQ7/3dPi7FkPUIbvneTSGgJYNDxJdHsDJ8OBHZ3BoqUJFDbTzFfVJjEzN4G9XQwPDafZ2p5WyerOK8Twj/rvk5N+ERmkt1XgVLQl66we/BO1ugTeM3YpDHm5lTzFUitJGTIuuONsKG9mmzdAmVUJ9YIrSxwmOBdegbGA+LAl5acg5VOol3KxRgZUMJQRQ58zpBAs72oauHizv1QVoQ7uIUiCUeb9lym+TEjmApvhru/1CPHU90K5jHNZ57wb/4V9VsqBWuoNibzDWG35YTFLcx0o+1lrCIjm1QjuC0777G+L1HNw5wnppV3z/k0YujjuPS3wvOA30TjHg';

/// Where the vodozemac library is, or null: the encrypted tests are then
/// skipped.
final vodozemacDir = Platform.environment['VODOZEMAC_LIB_DIR'];

/// Why the encrypted tests are skipped, or false.
Object get skipWithoutVodozemac => vodozemacDir == null
    ? 'VODOZEMAC_LIB_DIR is not set: no encryption here'
    : false;

/// Loads vodozemac from [vodozemacDir], as the flutter_rust_bridge loader
/// takes it: through `Uri.resolve`, so `C:/x` must be `/C:/x/`.
Future<void> initVodozemac() async {
  final dir = vodozemacDir;
  if (dir == null || vod.isInitialized()) return;
  var path = dir.replaceAll(r'\', '/');
  if (!path.startsWith('/')) path = '/$path';
  await vod.init(libraryPath: path.endsWith('/') ? path : '$path/');
}

/// [LoopTransport] with only us in the room, so its keys go to no one. The
/// answer of a `PUT /send` waits for [holdSend] when it is set.
class OnlyUsTransport extends LoopTransport {
  Completer<void>? holdSend;
  int sendsArrived = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'PUT' && request.url.path.contains('/send/')) {
      sendsArrived++;
      final hold = holdSend;
      if (hold != null) {
        final answer = await super.send(request);
        await hold.future;
        return answer;
      }
    }
    if (request.method == 'GET' && request.url.path.endsWith('/members')) {
      return json(200, {
        'chunk': [
          {
            'type': 'm.room.member',
            'state_key': '@test:fakeServer.notExisting',
            'sender': '@test:fakeServer.notExisting',
            'event_id': r'$join',
            'origin_server_ts': 0,
            'content': {'membership': 'join'},
          }
        ]
      });
    }
    return super.send(request);
  }
}

matrix.MatrixEvent _encryptionState(matrix.Client mx) => matrix.MatrixEvent(
      type: matrix.EventTypes.Encryption,
      stateKey: '',
      senderId: mx.userID!,
      eventId: '\$encryption',
      originServerTs: DateTime.now(),
      content: {'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2},
    );

/// A `matrix.Client` with encryption on [transport], and the room it has
/// joined, [encrypted] or not.
Future<(matrix.Client, matrix.Room)> cryptoClient(
    String name, LoopTransport transport,
    {required bool encrypted}) async {
  final database = await matrix.MatrixSdkDatabase.init(
    name,
    database: await databaseFactoryFfi.openDatabase(':memory:',
        options: OpenDatabaseOptions(singleInstance: false)),
    sqfliteFactory: databaseFactoryFfi,
  );
  final mx = matrix.Client(name,
      database: database, httpClient: transport, sendClock: ManualSendClock());
  FakeMatrixApi.client = mx;
  await mx.checkHomeserver(Uri.parse('https://fakeServer.notExisting'),
      checkWellKnown: false);
  await mx.init(
    newToken: 'abcd',
    newUserID: '@test:fakeServer.notExisting',
    newHomeserver: mx.homeserver,
    newDeviceName: 'Test client',
    newDeviceID: 'GHTYAJCE',
    newOlmAccount: _pickledOlmAccount,
  );
  await mx.abortSync();
  mx.backgroundSync = false;
  expect(mx.encryptionEnabled, isTrue);
  await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
        nextBatch: 'start',
        rooms: matrix.RoomsUpdate(join: {
          roomId: matrix.JoinedRoomUpdate(state: [
            matrix.MatrixEvent(
              type: matrix.EventTypes.RoomMember,
              stateKey: mx.userID,
              senderId: mx.userID!,
              eventId: '\$join',
              originServerTs: DateTime.now(),
              content: {'membership': 'join'},
            ),
            if (encrypted) _encryptionState(mx),
          ]),
        }),
      )));
  final room = mx.getRoomById(roomId)!;
  expect(room.encrypted, encrypted);
  return (mx, room);
}

/// The room of [mx] starts encrypting.
Future<void> turnOnEncryption(matrix.Client mx) =>
    mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
          nextBatch: 'now_encrypted',
          rooms: matrix.RoomsUpdate(join: {
            roomId: matrix.JoinedRoomUpdate(state: [_encryptionState(mx)]),
          }),
        )));

/// [sent], an encrypted event the transport received, decrypted.
Future<matrix.Event> decryptSent(matrix.Client mx, matrix.Room room,
        ({String type, String txid, Map<String, dynamic> body}) sent) =>
    mx.encryption!.decryptRoomEvent(matrix.Event(
      type: sent.type,
      content: sent.body,
      senderId: mx.userID!,
      eventId: '\$sent',
      originServerTs: DateTime.now(),
      room: room,
    ));

/// The bytes of the encrypted [file] (an event's `file` or
/// `thumbnail_file`) decrypted from [upload] with its own key and hash;
/// null when the hash does not match.
Future<Uint8List?> decryptUpload(Map<String, dynamic> file, Uint8List upload) =>
    matrix.decryptFileImplementation(matrix.EncryptedFile(
      data: upload,
      k: file['key']['k'] as String,
      iv: file['iv'] as String,
      sha256: file['hashes']['sha256'] as String,
    ));

/// How many of [uploads] are the test file or thumbnail as they are on
/// this device, not encrypted: every byte is what `startSend` fills them
/// with.
int clearUploads(List<Uint8List> uploads) => uploads
    .where((u) =>
        (u.length == fileBytes && u.every((b) => b == 1)) ||
        (u.length == thumbnailBytes && u.every((b) => b == 2)))
    .length;
