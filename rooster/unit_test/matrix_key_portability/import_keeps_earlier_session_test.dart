@TestOn('vm')
library;

// Reviewer test (T3.4 c1, finding c1-1): importing a key file must not
// replace a session the database already holds from an earlier index with
// the file's later one. The SDK compares indexes only against the sessions
// in memory, and after a restart none are in memory until a message
// needs them.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption/utils/session_key.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/components/key_portability/megolm_export_format.dart';
import 'package:rooster/client/matrix/components/key_portability/megolm_key_portability.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import '../room_keys/fake_homeserver.dart';
import '../room_keys/two_accounts.dart';

const _alice = '@alice:${FakeHomeserver.domain}';
const _text = 'Sent at index 0';
const _passphrase = 'a passphrase long enough';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MatrixClient pc;
  late String roomId;
  late String eventId;
  late Uint8List laterIndexFile;

  Future<int> storedFirstIndex() async {
    final client = pc.getMatrixClient();
    final stored = (await client.database.getAllInboundGroupSessions())
        .singleWhere((s) => s.roomId == roomId);
    return SessionKey.fromDb(stored, client.userID!)
        .inboundGroupSession!
        .firstKnownIndex;
  }

  setUpAll(() async {
    if (vodozemacSkip != false) return;
    await setUpEncryption();
    final server = FakeHomeserver();
    pc = await signIn(server, _alice, 'ALICEPC');
    final room = await pc.createRoom(CreateRoomArgs(
      name: 'Private',
      visibility: RoomVisibilityPrivate(),
      enableE2EE: true,
    )) as MatrixRoom;
    roomId = room.identifier;
    await until(() => room.matrixRoom.encrypted, what: 'encryption');
    eventId = (await room.matrixRoom.sendTextEvent(_text))!;

    // The same session, exported from index 1 (as a device that got it
    // late, or a forwarded copy, would hold it).
    final portability =
        MegolmKeyPortability(pc.getMatrixClient(), rounds: 1000);
    final session = (await portability.exportedSessions()).single;
    final later =
        vod.InboundGroupSession.import(session['session_key'] as String)
            .exportAt(1)!;
    laterIndexFile =
        Uint8List.fromList(utf8.encode(await MegolmExportFormat.encrypt([
      {...session, 'session_key': later}
    ], _passphrase, rounds: 1000)));
  });

  test('the database holds the session from index 0', skip: vodozemacSkip,
      () async {
    expect(await storedFirstIndex(), 0);
  });

  test('importing a later index while the session is in memory keeps index 0',
      skip: vodozemacSkip, () async {
    await MegolmKeyPortability(pc.getMatrixClient(), rounds: 1000)
        .importKeys(laterIndexFile, _passphrase);
    expect(await storedFirstIndex(), 0);
  });

  test(
      'importing a later index after a restart (nothing in memory) keeps '
      'index 0, and the first message still reads',
      skip: vodozemacSkip, () async {
    final keyManager = pc.getMatrixClient().encryption!.keyManager;
    // As after a restart: sessions load from the database when needed.
    keyManager.clearInboundGroupSessions();
    await MegolmKeyPortability(pc.getMatrixClient(), rounds: 1000)
        .importKeys(laterIndexFile, _passphrase);
    expect(await storedFirstIndex(), 0,
        reason: 'the import replaced the earlier session with a later one');
    keyManager.clearInboundGroupSessions();
    final event = await readEvent(pc.getRoom(roomId)! as MatrixRoom, eventId);
    expect(event!.type, matrix.EventTypes.Message);
  });
}
