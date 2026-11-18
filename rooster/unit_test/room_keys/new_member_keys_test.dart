@TestOn('vm')
library;

/// A new member of an encrypted room gets the room key of the first
/// message sent after they arrived, however soon it is sent: two Rooster
/// accounts with real encryption (vodozemac) on a homeserver in memory,
/// as in the e2e test where account 2 never decrypted account 1's text.
/// See docs/speed-log.md, "Room keys for new members".

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';

import '../text_send/text_send_fakes.dart' show setTypingNotices;
import 'fake_homeserver.dart';
import 'two_accounts.dart';

const _alice = '@alice:${FakeHomeserver.domain}';
const _bob = '@bob:${FakeHomeserver.domain}';
const _carol = '@carol:${FakeHomeserver.domain}';

/// How long the homeserver takes to answer `POST /keys/query`: a real one
/// over the internet, where the e2e test ran.
const _keysQueryLatency = Duration(milliseconds: 300);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHomeserver server;
  late MatrixClient alice;
  late MatrixClient bob;
  final signedIn = <MatrixClient>[];

  Future<MatrixClient> account(String userId, String deviceId) async {
    final client = await signIn(server, userId, deviceId);
    signedIn.add(client);
    return client;
  }

  setUp(() async {
    if (vodozemacSkip != false) return;
    await setUpEncryption();
    server = FakeHomeserver()..keysQueryLatency = _keysQueryLatency;
    signedIn.clear();
    alice = await account(_alice, 'ALICEPC');
    bob = await account(_bob, 'BOBPC');
  });

  tearDown(() async {
    for (final client in signedIn) {
      await client.close();
    }
  });

  /// Account 1's new private encrypted room, made as the app makes it.
  Future<MatrixRoom> createEncryptedRoom() async {
    final room = await alice.createRoom(CreateRoomArgs(
      name: 'Private',
      visibility: RoomVisibilityPrivate(),
      enableE2EE: true,
    )) as MatrixRoom;
    await until(() => room.matrixRoom.encrypted, what: 'encryption on');
    return room;
  }

  /// Account 1 invites account 2, and waits until it sees the invite.
  Future<void> invite(MatrixRoom room) async {
    await room.matrixRoom.invite(_bob);
    await until(() => hasMember(room, _bob, [matrix.Membership.invite]),
        what: 'account 2 invited');
  }

  /// Account 1 invites account 2 and account 2 joins, both seen by
  /// account 1 in one sync, as the e2e test does them one right after the
  /// other; account 1 waits until it sees account 2 in.
  Future<void> inviteAndJoin(MatrixRoom room) async {
    server.holdSync.add(_alice);
    await room.matrixRoom.invite(_bob);
    await bob.joinRoom(room.identifier);
    server.releaseSync(_alice);
    await until(() => hasMember(room, _bob), what: 'account 2 joined');
  }

  /// Account 1 sends [text] the way the composer does; the event's id.
  Future<String> send(MatrixRoom room, String text) async {
    final event = await room.sendMessage(message: text);
    return event!.eventId;
  }

  /// The text of [eventId] once [client] decrypted it, or null when it is
  /// still encrypted 5 s later.
  Future<String?> decryptedOn(
      MatrixClient client, String roomId, String eventId) async {
    final room = await roomOf(client, roomId);
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(end)) {
      final event = await readEvent(room, eventId);
      if (event != null && event.type == matrix.EventTypes.Message) {
        return event.body;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  /// Account 1 readies the room's session the way a first keystroke does,
  /// with typing notices on (T4.1, T6.13), and waits until it is made.
  Future<void> startTyping(MatrixRoom room) async {
    await setTypingNotices(alice, true);
    room.prepareToSend();
    await until(
        () =>
            alice
                .getMatrixClient()
                .encryption!
                .keyManager
                .getOutboundGroupSession(room.identifier) !=
            null,
        what: 'the session made ahead');
  }

  test(
      'the e2e case: account 1 creates the encrypted room, invites account '
      '2, account 2 joins, account 1 sends at once: account 2 decrypts',
      skip: vodozemacSkip, () async {
    final room = await createEncryptedRoom();
    await inviteAndJoin(room);
    final id = await send(room, 'Hello');
    expect(await decryptedOn(bob, room.identifier, id), 'Hello');
  });

  test(
      'account 2 joins before account 1 types (the session made ahead at '
      'the first keystroke): account 2 decrypts',
      skip: vodozemacSkip, () async {
    final room = await createEncryptedRoom();
    await inviteAndJoin(room);
    await startTyping(room);
    final id = await send(room, 'Typed after you came');
    expect(await decryptedOn(bob, room.identifier, id), 'Typed after you came');
  });

  test(
      'account 1 starts typing before account 2 is in the room, account 2 '
      'joins, account 1 sends: account 2 decrypts',
      skip: vodozemacSkip, () async {
    final room = await createEncryptedRoom();
    await startTyping(room);
    await inviteAndJoin(room);
    final id = await send(room, 'Started before you came');
    expect(
        await decryptedOn(bob, room.identifier, id), 'Started before you came');
  });

  test(
      'account 1 sends while account 2 is only invited: account 2 joins '
      'and decrypts',
      skip: vodozemacSkip, () async {
    final room = await createEncryptedRoom();
    await invite(room);
    final id = await send(room, 'Before you joined');
    await bob.joinRoom(room.identifier);
    expect(await decryptedOn(bob, room.identifier, id), 'Before you joined');
  });

  test('account 2 on two devices: both decrypt', skip: vodozemacSkip, () async {
    final phone = await account(_bob, 'BOBPHONE');
    final room = await createEncryptedRoom();
    await inviteAndJoin(room);
    final id = await send(room, 'To both');
    expect(await decryptedOn(bob, room.identifier, id), 'To both');
    expect(await decryptedOn(phone, room.identifier, id), 'To both');
  });

  test(
      'nothing leaves in clear, and the key goes only to the members: an '
      'account outside the room gets nothing',
      skip: vodozemacSkip, () async {
    final carol = await account(_carol, 'CAROLPC');
    final room = await createEncryptedRoom();
    await inviteAndJoin(room);
    final id = await send(room, 'Only for us');
    expect(await decryptedOn(bob, room.identifier, id), 'Only for us');

    final sends = server.requests[_alice]!
        .where((r) => r.startsWith('PUT /rooms/{id}/send/'));
    expect(sends, isNotEmpty);
    expect(sends,
        everyElement(startsWith('PUT /rooms/{id}/send/m.room.encrypted/')));
    expect(server.encryptedToDeviceTo(_bob), greaterThan(0));
    expect(server.encryptedToDeviceTo(_carol), 0);
    expect(carol.getRoom(room.identifier), isNull);
  });

  test(
      'the policy stays: a device its owner did not cross-sign, when they '
      'set up cross-signing, gets no key; the log says how many were left '
      'out, with no ids',
      skip: vodozemacSkip, () async {
    server.masterKeys[_bob] = 'B' * 43;
    final room = await createEncryptedRoom();
    await inviteAndJoin(room);
    final logged = matrix.Logs().outputEvents.length;
    final id = await send(room, 'Not for an unsigned device');
    expect(await decryptedOn(bob, room.identifier, id), isNull);
    expect(server.encryptedToDeviceTo(_bob), 0);
    final lines = [
      for (final e in matrix.Logs().outputEvents.skip(logged)) e.title,
    ].where((t) => t.contains('leaves out'));
    expect(lines, [
      "[KeyManager] The room key leaves out 1 device(s) of the room's "
          'members: blocked, or not cross-signed by their owner',
    ]);
  });
}
