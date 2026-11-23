@TestOn('vm')
library;

/// The security case behind the profile's Block button: once account 1
/// blocks one of account 2's two devices, the next room session (Megolm)
/// is a new one, and the blocked device gets no `m.room_key` for it and
/// cannot read the message. Real encryption (vodozemac) on a homeserver
/// in memory; the block goes through the same call the profile makes.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/ui/organisms/user_profile/user_devices.dart';

import '../room_keys/fake_homeserver.dart';
import '../room_keys/two_accounts.dart';

const _alice = '@alice:${FakeHomeserver.domain}';
const _bob = '@bob:${FakeHomeserver.domain}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHomeserver server;
  late MatrixClient alice;
  late MatrixClient bobPc;
  late MatrixClient bobPhone;
  final signedIn = <MatrixClient>[];
  final subs = <StreamSubscription>[];

  /// The Megolm session ids [client]'s device received as `m.room_key`.
  final roomKeys = <MatrixClient, List<String>>{};

  Future<MatrixClient> account(String userId, String deviceId) async {
    final client = await signIn(server, userId, deviceId);
    signedIn.add(client);
    final received = roomKeys[client] = [];
    subs.add(client.matrixClient.onToDeviceEvent.stream.listen((event) {
      if (event.type == matrix.EventTypes.RoomKey) {
        received.add(event.content['session_id'] as String);
      }
    }));
    return client;
  }

  setUp(() async {
    if (vodozemacSkip != false) return;
    await setUpEncryption();
    server = FakeHomeserver();
    signedIn.clear();
    roomKeys.clear();
    alice = await account(_alice, 'ALICEPC');
    bobPc = await account(_bob, 'BOBPC');
    bobPhone = await account(_bob, 'BOBPHONE');
  });

  tearDown(() async {
    for (final sub in subs) {
      await sub.cancel();
    }
    subs.clear();
    for (final client in signedIn) {
      await client.close();
    }
  });

  Future<MatrixRoom> encryptedRoomWithBob() async {
    final room = await alice.createRoom(CreateRoomArgs(
      name: 'Private',
      visibility: RoomVisibilityPrivate(),
      enableE2EE: true,
    )) as MatrixRoom;
    await until(() => room.matrixRoom.encrypted, what: 'encryption on');
    await room.matrixRoom.invite(_bob);
    await bobPc.joinRoom(room.identifier);
    await until(() => hasMember(room, _bob), what: 'account 2 joined');
    return room;
  }

  /// Account 1 sends [text]; the event's id and its Megolm session.
  Future<(String, String)> send(MatrixRoom room, String text) async {
    final event = await room.sendMessage(message: text);
    final session = alice.matrixClient.encryption!.keyManager
        .getOutboundGroupSession(room.identifier)!
        .outboundGroupSession!
        .sessionId;
    return (event!.eventId, session);
  }

  /// The text of [eventId] on [client] once it decrypts, or null when it
  /// is still encrypted after [wait].
  Future<String?> decryptedOn(
      MatrixClient client, String roomId, String eventId,
      {Duration wait = const Duration(seconds: 5)}) async {
    final room = await roomOf(client, roomId);
    final end = DateTime.now().add(wait);
    while (DateTime.now().isBefore(end)) {
      final event = await readEvent(room, eventId);
      if (event != null && event.type == matrix.EventTypes.Message) {
        return event.body;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  test(
      'after blocking one of their devices, the next room session leaves it '
      'out: no m.room_key, no decryption; their other device still reads',
      skip: vodozemacSkip, () async {
    final room = await encryptedRoomWithBob();

    // Before: both of account 2's devices get the key and read.
    final (before, first) = await send(room, 'Before the block');
    expect(
        await decryptedOn(bobPc, room.identifier, before), 'Before the block');
    expect(await decryptedOn(bobPhone, room.identifier, before),
        'Before the block');
    expect(roomKeys[bobPhone], contains(first));

    // The profile's Block button.
    await UserDevices.setBlocked(alice.matrixClient, _bob, 'BOBPHONE', true);
    expect(
        alice
            .matrixClient.userDeviceKeys[_bob]!.deviceKeys['BOBPHONE']!.blocked,
        isTrue);
    expect(
        UserDevices.of(alice.matrixClient, _bob)
            .singleWhere((d) => d.deviceId == 'BOBPHONE')
            .blocked,
        isTrue);

    final (after, second) = await send(room, 'After the block');
    expect(second, isNot(first), reason: 'a new session after the block');
    final outbound = alice.matrixClient.encryption!.keyManager
        .getOutboundGroupSession(room.identifier)!;
    expect(outbound.devices[_bob], {'BOBPC': false, 'BOBPHONE': true},
        reason: 'the session records the phone as blocked');

    expect(await decryptedOn(bobPc, room.identifier, after), 'After the block');
    expect(roomKeys[bobPc], contains(second));
    expect(await decryptedOn(bobPhone, room.identifier, after), isNull,
        reason: 'the blocked device cannot read it');
    expect(roomKeys[bobPhone], isNot(contains(second)),
        reason: 'the blocked device got no m.room_key for the new session');
    expect(
        await bobPhone.matrixClient.encryption!.keyManager
            .loadInboundGroupSession(room.identifier, second),
        isNull);
  });

  test('unblocking sends the device the keys of the messages that follow',
      skip: vodozemacSkip, () async {
    final room = await encryptedRoomWithBob();
    await UserDevices.setBlocked(alice.matrixClient, _bob, 'BOBPHONE', true);
    final (blocked, _) = await send(room, 'While blocked');
    expect(await decryptedOn(bobPc, room.identifier, blocked), 'While blocked');
    expect(
        await decryptedOn(bobPhone, room.identifier, blocked,
            wait: const Duration(seconds: 2)),
        isNull);

    await UserDevices.setBlocked(alice.matrixClient, _bob, 'BOBPHONE', false);
    final (again, session) = await send(room, 'Unblocked');

    expect(await decryptedOn(bobPhone, room.identifier, again), 'Unblocked');
    expect(roomKeys[bobPhone], contains(session));
  });

  test(
      'blocking a device that is not known fails, translated, and changes '
      'nothing',
      skip: vodozemacSkip, () async {
    await alice.matrixClient.updateUserDeviceKeys(additionalUsers: {_bob});
    await expectLater(
        UserDevices.setBlocked(alice.matrixClient, _bob, 'NOSUCHDEVICE', true),
        throwsA(isA<UserDeviceChangeFailed>()));
    expect(UserDevices.of(alice.matrixClient, _bob).map((d) => d.blocked),
        everyElement(isFalse));
  });
}
