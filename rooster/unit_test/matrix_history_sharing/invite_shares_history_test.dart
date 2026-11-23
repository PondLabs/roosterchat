@TestOn('vm')
library;

/// The room's switch decides what an invite from the app shares, with real
/// encryption (vodozemac) on a homeserver in memory: off, the invite uploads
/// no bundle and sends the invitee no key; on, it does both.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/components/history_sharing/matrix_history_sharing.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../room_keys/fake_homeserver.dart';
import '../room_keys/two_accounts.dart';

const _alice = '@alice:${FakeHomeserver.domain}';
const _bob = '@bob:${FakeHomeserver.domain}';

/// The fake homeserver with a media repository in front: it takes the
/// uploads (the server reads every body as JSON) and counts them, and says
/// which versions it speaks, which an upload asks first.
class _WithUploads extends http.BaseClient {
  _WithUploads(this.inner);

  final http.Client inner;
  int uploads = 0;

  static http.StreamedResponse _json(Object body) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
          headers: {'content-type': 'application/json'});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/client/versions')) {
      return _json({
        'versions': ['v1.1', 'v1.6', 'v1.11'],
      });
    }
    if (request.method == 'POST' &&
        request.url.path.endsWith('/media/v3/upload')) {
      await request.finalize().drain<void>();
      uploads++;
      return _json({
        'content_uri': 'mxc://${FakeHomeserver.domain}/bundle$uploads',
      });
    }
    return inner.send(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHomeserver server;
  late _WithUploads transport;
  late MatrixClient alice;
  late MatrixClient bob;

  setUp(() async {
    if (vodozemacSkip != false) return;
    await setUpEncryption();
    server = FakeHomeserver();
    transport = _WithUploads(server.transport);
    // As `signIn` does, on the transport that takes uploads.
    alice = MatrixClient(
      identifier: 'history_sharing_alice',
      database: await matrix.MatrixSdkDatabase.init(
        'history_sharing_alice',
        database: await databaseFactoryFfi.openDatabase(':memory:',
            options: OpenDatabaseOptions(singleInstance: false)),
        sqfliteFactory: databaseFactoryFfi,
      ),
      transport: transport,
    );
    await alice.getMatrixClient().init(
          newToken: server.addDevice(_alice, 'ALICEPC'),
          newUserID: _alice,
          newHomeserver: Uri.parse('https://${FakeHomeserver.domain}'),
          newDeviceName: 'ALICEPC',
          newDeviceID: 'ALICEPC',
        );
    bob = await signIn(server, _bob, 'BOBPHONE');
  });

  tearDown(() async {
    if (vodozemacSkip != false) return;
    await alice.close();
    await bob.close();
  });

  test('the switch off shares nothing on invite, on it shares the history',
      () async {
    final room = await alice.createRoom(CreateRoomArgs(
      name: 'Private',
      visibility: RoomVisibilityPrivate(),
      enableE2EE: true,
    )) as MatrixRoom;
    final mxRoom = room.matrixRoom;
    await until(() => mxRoom.encrypted, what: 'encryption on');
    await mxRoom.sendTextEvent('said before the invite');
    final mx = alice.getMatrixClient();
    final sharing = MatrixHistorySharing(mxRoom);
    expect(sharing.state, HistorySharingState.on);

    await sharing.setShareOnInvite(false);
    await MatrixHistorySharing.invite(mx, mxRoom.id, _bob);
    await until(() => hasMember(room, _bob, [matrix.Membership.invite]),
        what: 'the invite');
    expect(transport.uploads, 0);
    expect(server.encryptedToDeviceTo(_bob), 0);

    await sharing.setShareOnInvite(true);
    await MatrixHistorySharing.invite(mx, mxRoom.id, _bob);
    expect(transport.uploads, 1);
    expect(server.encryptedToDeviceTo(_bob), 1);
  }, skip: vodozemacSkip);
}
