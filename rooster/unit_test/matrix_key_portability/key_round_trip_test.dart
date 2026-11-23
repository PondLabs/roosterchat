@TestOn('vm')
library;

/// The room keys of one session, exported to a file and imported on a new
/// session of the same account, with real encryption (vodozemac) on a
/// homeserver in memory: the new session reads the message only after
/// the import, and a wrong passphrase or a file cut short leave its
/// database as it was.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/components/key_portability/megolm_export_format.dart';
import 'package:rooster/client/matrix/components/key_portability/megolm_key_portability.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';

import '../room_keys/fake_homeserver.dart';
import '../room_keys/two_accounts.dart';

const _alice = '@alice:${FakeHomeserver.domain}';
const _text = 'Read me on the new session';
const _passphrase = 'a passphrase long enough';

Matcher _fails(MegolmExportError error) => throwsA(
    isA<MegolmExportException>().having((e) => e.error, 'error', error));

/// What [client]'s database holds of room key sessions, as ids and pickles.
Future<List<String>> _stored(MatrixClient client) async => [
      for (final session in await client
          .getMatrixClient()
          .database
          .getAllInboundGroupSessions())
        '${session.roomId}|${session.sessionId}|${session.pickle}',
    ]..sort();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHomeserver server;
  late String roomId;
  late String eventId;
  late Uint8List file;
  late int exported;
  late MatrixClient newSession;

  setUpAll(() async {
    if (vodozemacSkip != false) return;
    await setUpEncryption();
    server = FakeHomeserver();
    final pc = await signIn(server, _alice, 'ALICEPC');
    final pcRoom = await pc.createRoom(CreateRoomArgs(
      name: 'Private',
      visibility: RoomVisibilityPrivate(),
      enableE2EE: true,
    )) as MatrixRoom;
    roomId = pcRoom.identifier;
    await until(() => pcRoom.matrixRoom.encrypted, what: 'encryption');
    eventId = (await pcRoom.matrixRoom.sendTextEvent(_text))!;

    final export =
        await MegolmKeyPortability(pc.getMatrixClient(), rounds: 1000)
            .exportKeys(_passphrase);
    file = export.file;
    exported = export.count;
    // The first session goes: nobody is left to share the key again.
    await pc.getMatrixClient().dispose(closeDatabase: false);

    newSession = await signIn(server, _alice, 'ALICENEW');
    await roomOf(newSession, roomId);
  });

  Future<matrix.Event?> message() async =>
      readEvent(await roomOf(newSession, roomId), eventId);

  MegolmKeyPortability portability() =>
      MegolmKeyPortability(newSession.getMatrixClient(), rounds: 1000);

  test('exports in the spec format', skip: vodozemacSkip, () async {
    final text = utf8.decode(file);
    expect(text, startsWith('-----BEGIN MEGOLM SESSION DATA-----\n'));
    expect(text.trimRight(), endsWith('-----END MEGOLM SESSION DATA-----'));
    expect(exported, 1);
    final sessions = await MegolmExportFormat.decrypt(file, _passphrase);
    expect(sessions.single.keys, {
      'algorithm',
      'forwarding_curve25519_key_chain',
      'room_id',
      'sender_key',
      'sender_claimed_keys',
      'session_id',
      'session_key',
    });
    expect(sessions.single['room_id'], roomId);
    expect(sessions.single['algorithm'], 'm.megolm.v1.aes-sha2');
    expect(text, isNot(contains(_passphrase)));
  });

  test('before the import the new session cannot read the message',
      skip: vodozemacSkip, () async {
    expect((await message())!.type, matrix.EventTypes.Encrypted);
  });

  test('a wrong passphrase fails and keeps nothing', skip: vodozemacSkip,
      () async {
    final before = await _stored(newSession);
    await expectLater(portability().importKeys(file, 'not the passphrase'),
        _fails(MegolmExportError.wrongPassphrase));
    expect(await _stored(newSession), before);
    expect((await message())!.type, matrix.EventTypes.Encrypted);
  });

  test('a file cut short fails and keeps nothing', skip: vodozemacSkip,
      () async {
    final before = await _stored(newSession);
    final half = Uint8List.sublistView(file, 0, file.length ~/ 2);
    await expectLater(portability().importKeys(half, _passphrase),
        _fails(MegolmExportError.damaged));
    expect(await _stored(newSession), before);
    expect((await message())!.type, matrix.EventTypes.Encrypted);
  });

  test('with the passphrase the keys come back and the message reads',
      skip: vodozemacSkip, () async {
    final result = await portability().importKeys(file, _passphrase);
    expect(result.total, 1);
    expect(result.imported, 1);
    final event = await message();
    expect(event!.type, matrix.EventTypes.Message);
    expect(event.body, _text);

    // Kept in the database too, not only in memory.
    final session = (await MegolmExportFormat.decrypt(file, _passphrase))
        .single['session_id'] as String;
    expect(
        await _stored(newSession), contains(startsWith('$roomId|$session|')));
  });

  test('entries that are not usable sessions are counted and skipped',
      skip: vodozemacSkip, () async {
    final good = await MegolmExportFormat.decrypt(file, _passphrase);
    final mixed = await MegolmExportFormat.encrypt([
      ...good,
      {'algorithm': 'm.megolm.v1.aes-sha2', 'room_id': roomId},
      {...good.single, 'session_id': 'not its id'},
      {...good.single, 'algorithm': 'm.olm.v1.curve25519-aes-sha2'},
    ], _passphrase, rounds: 1000);
    final before = await _stored(newSession);
    final result = await portability()
        .importKeys(Uint8List.fromList(utf8.encode(mixed)), _passphrase);
    expect(result.total, 4);
    expect(result.imported, 0);
    expect(result.alreadyHeld, 1);
    expect(result.unusable, 3);
    expect(await _stored(newSession), before,
        reason: 'the good one is already there, the others never are');
  });

  test('importing the same file again keeps nothing new', skip: vodozemacSkip,
      () async {
    final before = await _stored(newSession);
    // As after a restart: no session in memory.
    newSession
        .getMatrixClient()
        .encryption!
        .keyManager
        .clearInboundGroupSessions();
    final result = await portability().importKeys(file, _passphrase);
    expect(result.imported, 0);
    expect(result.alreadyHeld, 1);
    expect(result.unusable, 0);
    expect(await _stored(newSession), before);
  });
}
