@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import '../media_prepare/fakes.dart';
import '../pending_media/chat_harness.dart' show blackJpeg;
import '../pending_media/matrix_fakes.dart';
import '../speed_log/fake_account.dart';

const _roomId = '!1234:fakeServer.notExisting';

/// The olm account the SDK's own tests give `@test:fakeServer.notExisting`
/// (`third_party/matrix-dart-sdk/test/fake_client.dart`): the fake server
/// knows its keys.
const _pickledOlmAccount =
    'huxcPifHlyiQsX7cZeMMITbka3hLeUT3ss6DLL6dV7knaD4wgAYK6gcWknkixnX8C5KMIyxzytxiNqAOhDFRE5NsET8hr2dQ8OvXX7M95eQ7/3dPi7FkPUIbvneTSGgJYNDxJdHsDJ8OBHZ3BoqUJFDbTzFfVJjEzN4G9XQwPDafZ2p5WyerOK8Twj/rvk5N+ERmkt1XgVLQl66we/BO1ugTeM3YpDHm5lTzFUitJGTIuuONsKG9mmzdAmVUJ9YIrSxwmOBdegbGA+LAl5acg5VOol3KxRgZUMJQRQ58zpBAs72oauHizv1QVoQ7uIUiCUeb9lym+TEjmApvhru/1CPHU90K5jHNZ57wb/4V9VsqBWuoNibzDWG35YTFLcx0o+1lrCIjm1QjuC0777G+L1HNw5wnppV3z/k0YujjuPS3wvOA30TjHg';

/// The fake homeserver, with every `PUT /send` refused while [failSends]
/// (a Matrix error, as a homeserver gives it) and kept in [sends] as its
/// event type and body.
class _SendFails extends FakeTransport {
  bool failSends = false;
  int uploads = 0;
  final List<({String type, String txid, Map<String, dynamic> body})> sends =
      [];

  static http.StreamedResponse _json(int status, Object body) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          headers: {'content-type': 'application/json'});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.pathSegments;
    if (request.method == 'POST' && request.url.path.endsWith('/upload')) {
      uploads++;
      await request.finalize().drain<void>();
      return _json(
          200, {'content_uri': 'mxc://fakeServer.notExisting/u$uploads'});
    }
    if (request.method == 'GET' && request.url.path.endsWith('/members')) {
      // Who gets the room's keys: only us.
      return _json(200, {
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
    final at = path.indexOf('send');
    if (request.method == 'PUT' && at > 0 && path.length == at + 3) {
      final body = jsonDecode(utf8.decode(await request.finalize().toBytes()))
          as Map<String, dynamic>;
      sends.add((type: path[at + 1], txid: path[at + 2], body: body));
      if (failSends) {
        return _json(500, {'errcode': 'M_UNKNOWN', 'error': 'Try later'});
      }
      return _json(200, {'event_id': '\$sent${sends.length}'});
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final appPreparer = ImagePreparer.instance;

  tearDown(() {
    ImagePreparer.instance = appPreparer;
    AttachmentSends.instance.clear();
  });

  test(
      '"Retry" after the upload went through and PUT /send failed sends the '
      'same event again: 1 PUT /send under the same transaction, 0 uploads',
      () async {
    AttachmentSends.instance.clear();
    ImagePreparer.instance = fakePreparer(FakeEngine(width: 400, height: 300));
    final transport = _SendFails();
    final client = await fakeAccount('retry_after_upload', transport);
    final mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    final room = await plainRoom(client);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);

    transport.failSends = true;
    composerSend(room, attachments: [
      PendingFileAttachment(name: 'photo.jpg', data: blackJpeg(400, 300))
    ]).send();
    final send = AttachmentSends.instance.all.single;
    await until(() => send.isFinished);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final txid = send.transactionId!;
    final failed = echoes.lastWhere((e) => e.eventId == txid);
    expect(failed.status.isError, isTrue);
    expect(send.stage, AttachmentSendStage.failed);
    expect(room.matrixRoom.sendingFilePlaceholders, isNot(contains(txid)),
        reason: 'the SDK let the file go after it tried the event');
    final uploads = transport.uploads;
    final firstTry = transport.sends.last;
    expect(uploads, greaterThan(0));

    transport.failSends = false;
    final sendsBefore = transport.sends.length;
    await room.retrySend(room.convertEvent(failed));
    await until(() => send.isFinished);

    print('uploads before ${uploads}, after ${transport.uploads}; '
        'PUT /send after retry: ${transport.sends.length - sendsBefore}');
    expect(transport.uploads, uploads, reason: 'no new upload');
    final again = transport.sends.skip(sendsBefore).toList();
    expect(again, hasLength(1));
    expect(again.single.txid, txid);
    expect(again.single.type, 'm.room.message');
    expect(again.single.body['url'], firstTry.body['url']);
    expect(again.single.body['info'], firstTry.body['info']);
    expect(send.stage, AttachmentSendStage.sent);
    expect(
        echoes.any((e) =>
            e.eventId == '\$sent${transport.sends.length}' && e.status.isSent),
        isTrue,
        reason: 'the message is sent');
    await client.close();
  });

  final vodozemac = Platform.environment['VODOZEMAC_LIB_DIR'];
  test(
      'in an encrypted room the event sent again is the encrypted one: its '
      'file stays encrypted and nothing goes out in the clear',
      skip: vodozemac == null
          ? 'VODOZEMAC_LIB_DIR is not set: no encryption here'
          : false, () async {
    if (!vod.isInitialized())
      await vod.init(libraryPath: _libraryDir(vodozemac!));
    final transport = _SendFails();
    final database = await matrix.MatrixSdkDatabase.init(
      'retry_encrypted',
      database: await databaseFactoryFfi.openDatabase(':memory:',
          options: OpenDatabaseOptions(singleInstance: false)),
      sqfliteFactory: databaseFactoryFfi,
    );
    final mx = matrix.Client('retry_encrypted',
        database: database, httpClient: transport);
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
            _roomId: matrix.JoinedRoomUpdate(state: [
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
    final room = mx.getRoomById(_roomId)!;
    expect(room.encrypted, isTrue);
    final echoes = <matrix.Event>[];
    mx.onTimelineEvent.stream.listen(echoes.add);

    transport.failSends = true;
    final send = AttachmentSend(roomKey: 'test:$_roomId', attachment: null);
    final file = matrix.MatrixFile(
        bytes: Uint8List.fromList(List.filled(4000, 7)), name: 'notes.bin');
    expect(await sendMatrixFile(room, TrackedMatrixAttachment(file, send)),
        isNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final txid = send.transactionId!;
    final failed = echoes.lastWhere((e) => e.eventId == txid);
    expect(failed.status.isError, isTrue);
    expect(failed.content['file'], isA<Map>(),
        reason: 'the upload was the encrypted file');
    expect(failed.content['url'], isNull);
    final uploads = transport.uploads;

    transport.failSends = false;
    final sendsBefore = transport.sends.length;
    await resendUploadedFile(failed, send);

    final again = transport.sends.skip(sendsBefore).toList();
    print('encrypted retry: ${again.map((s) => '${s.type} ${s.body.keys}')}');
    expect(transport.uploads, uploads);
    expect(again, hasLength(1));
    expect(again.single.txid, txid);
    expect(again.single.type, 'm.room.encrypted');
    expect(again.single.body['ciphertext'], isA<String>());
    final wire = jsonEncode(again.single.body);
    expect(wire, isNot(contains('notes.bin')));
    expect(wire, isNot(contains('mxc://')));
    expect(send.stage, AttachmentSendStage.sent);
    await mx.dispose(closeDatabase: true);
  });
}
