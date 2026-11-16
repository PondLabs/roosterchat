@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'loop_fakes.dart';

/// The olm account the SDK's own tests give `@test:fakeServer.notExisting`
/// (`third_party/matrix-dart-sdk/test/fake_client.dart`): the fake server
/// knows its keys.
const _pickledOlmAccount =
    'huxcPifHlyiQsX7cZeMMITbka3hLeUT3ss6DLL6dV7knaD4wgAYK6gcWknkixnX8C5KMIyxzytxiNqAOhDFRE5NsET8hr2dQ8OvXX7M95eQ7/3dPi7FkPUIbvneTSGgJYNDxJdHsDJ8OBHZ3BoqUJFDbTzFfVJjEzN4G9XQwPDafZ2p5WyerOK8Twj/rvk5N+ERmkt1XgVLQl66we/BO1ugTeM3YpDHm5lTzFUitJGTIuuONsKG9mmzdAmVUJ9YIrSxwmOBdegbGA+LAl5acg5VOol3KxRgZUMJQRQ58zpBAs72oauHizv1QVoQ7uIUiCUeb9lym+TEjmApvhru/1CPHU90K5jHNZ57wb/4V9VsqBWuoNibzDWG35YTFLcx0o+1lrCIjm1QjuC0777G+L1HNw5wnppV3z/k0YujjuPS3wvOA30TjHg';

/// [LoopTransport] with only us in the room, so its keys go to no one.
class _OnlyUs extends LoopTransport {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
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

/// [dir] as the flutter_rust_bridge loader takes it: it goes through
/// `Uri.resolve`, so `C:/x` must be `/C:/x/` (a shell may drop the slash).
String _libraryDir(String dir) {
  var path = dir.replaceAll(r'\', '/');
  if (!path.startsWith('/')) path = '/$path';
  return path.endsWith('/') ? path : '$path/';
}

/// The bytes of the encrypted [file] (an event's `file` or
/// `thumbnail_file`) decrypted from [upload] with its own key and hash;
/// null when the hash does not match.
Future<Uint8List?> _decrypt(Map<String, dynamic> file, Uint8List upload) =>
    matrix.decryptFileImplementation(matrix.EncryptedFile(
      data: upload,
      k: file['key']['k'] as String,
      iv: file['iv'] as String,
      sha256: file['hashes']['sha256'] as String,
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());

  final vodozemac = Platform.environment['VODOZEMAC_LIB_DIR'];
  test(
      'in an encrypted room the file kept from a failed send is reused with '
      'the key and hash the event carries: what the server got decrypts '
      'with them',
      skip: vodozemac == null
          ? 'VODOZEMAC_LIB_DIR is not set: no encryption here'
          : false, () async {
    if (!vod.isInitialized()) {
      await vod.init(libraryPath: _libraryDir(vodozemac!));
    }
    final transport = _OnlyUs();
    transport.onUpload = (body, attempt) async {
      // The thumbnail is refused the first time: the send ends.
      if (body.length == thumbnailBytes && attempt == 1) {
        return json(403, {'errcode': 'M_FORBIDDEN', 'error': 'Not now'});
      }
      return transport.accept(body);
    };
    final database = await matrix.MatrixSdkDatabase.init(
      'loop_encrypted',
      database: await databaseFactoryFfi.openDatabase(':memory:',
          options: OpenDatabaseOptions(singleInstance: false)),
      sqfliteFactory: databaseFactoryFfi,
    );
    final mx = matrix.Client('loop_encrypted',
        database: database,
        httpClient: transport,
        sendClock: ManualSendClock());
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
          nextBatch: 'encrypted',
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
              matrix.MatrixEvent(
                type: matrix.EventTypes.Encryption,
                stateKey: '',
                senderId: mx.userID!,
                eventId: '\$encryption',
                originServerTs: DateTime.now(),
                content: {'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2},
              ),
            ]),
          }),
        )));
    final room = mx.getRoomById(roomId)!;
    expect(room.encrypted, isTrue);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);

    final (send, sending) = startSend(room);
    expect(await sending, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final txid = send.transactionId!;
    final kept = room.sendingFileUploads[txid]![matrix.FileSendPart.file]!;
    final keptKey = kept.encryptedFile!.k;
    expect(room.sendingFileUploads[txid]!.keys, [matrix.FileSendPart.file]);
    final failed = echoes.lastWhere((e) => e.eventId == txid);
    expect(failed.status.isError, isTrue);
    expect(transport.uploadsOf(fileBytes), 1);

    // "Retry", as the menu does it.
    expect(await retryMatrixFile(failed, send), isNotNull);

    print('encrypted retry: ${transport.byRoute}; file uploads '
        '${transport.uploadsOf(fileBytes)}, thumbnail uploads '
        '${transport.uploadsOf(thumbnailBytes)}');
    expect(transport.uploadsOf(fileBytes), 1, reason: 'the kept file');
    expect(transport.uploadsOf(thumbnailBytes), 2);
    final sent = transport.events.single;
    expect(sent.txid, txid);
    expect(sent.type, matrix.EventTypes.Encrypted);
    expect(jsonEncode(sent.body), isNot(contains('mxc://')));

    final event = await mx.encryption!.decryptRoomEvent(matrix.Event(
      type: sent.type,
      content: sent.body,
      senderId: mx.userID!,
      eventId: '\$sent',
      originServerTs: DateTime.now(),
      room: room,
    ));
    expect(event.type, matrix.EventTypes.Message);
    final file = event.content['file'] as Map<String, dynamic>;
    expect(file['url'], kept.uri.toString());
    expect(file['key']['k'], keptKey, reason: 'the same key as it went up');
    final fileUpload =
        transport.uploads.firstWhere((u) => u.length == fileBytes);
    expect(
        await _decrypt(file, fileUpload), List.filled(fileBytes, 1).toList());
    final thumbnail = (event.content['info'] as Map)['thumbnail_file']
        as Map<String, dynamic>;
    final thumbnailUpload =
        transport.uploads.lastWhere((u) => u.length == thumbnailBytes);
    expect(await _decrypt(thumbnail, thumbnailUpload),
        List.filled(thumbnailBytes, 2).toList());
    expect(send.stage, AttachmentSendStage.sent);
    await mx.dispose(closeDatabase: true);
  });
}
