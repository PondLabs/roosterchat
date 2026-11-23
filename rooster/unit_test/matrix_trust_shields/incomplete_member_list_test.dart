@TestOn('vm')
library;

/// Review c1-1: the room shield must not say "Verified" while the room's
/// member list is only partly loaded (lazy-loaded members). Account 3 is
/// in the room and not verified, but its membership has not reached
/// account 1 yet, as with `lazy_load_members` before the first send.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/ui/atoms/e2ee_trust_shield.dart';
import 'package:rooster/ui/molecules/profile/e2ee_trust.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../room_keys/fake_homeserver.dart';
import '../room_keys/two_accounts.dart';

const _alice = '@alice:${FakeHomeserver.domain}';
const _bob = '@bob:${FakeHomeserver.domain}';
const _carol = '@carol:${FakeHomeserver.domain}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'a room whose member list is not fully loaded is not shown as '
      'verified',
      skip: vodozemacSkip, () async {
    await setUpEncryption();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    VerifiedIdentities.resetForTest();
    final server = FakeHomeserver();
    final alice = await signIn(server, _alice, 'ALICEPC');
    final bob = await signIn(server, _bob, 'BOBPC');
    final carol = await signIn(server, _carol, 'CAROLPC');
    addTearDown(() async {
      for (final c in <MatrixClient>[alice, bob, carol]) {
        await c.close();
      }
    });

    final room = await alice.createRoom(CreateRoomArgs(
      name: 'Private',
      visibility: RoomVisibilityPrivate(),
      enableE2EE: true,
    )) as MatrixRoom;
    await until(() => room.matrixRoom.encrypted, what: 'encryption on');
    await room.matrixRoom.invite(_bob);
    await room.matrixRoom.invite(_carol);
    await bob.joinRoom(room.identifier);
    await carol.joinRoom(room.identifier);
    await until(() => hasMember(room, _bob) && hasMember(room, _carol),
        what: 'both joined');

    // Account 1 verified account 2 (identity and device), not account 3.
    server.masterKeys[_bob] = 'A' * 43;
    alice.matrixClient.userDeviceKeys[_bob]?.outdated = true;
    await alice.matrixClient
        .updateUserDeviceKeys(additionalUsers: {_bob, _carol});
    final bobKeys = alice.matrixClient.userDeviceKeys[_bob]!;
    bobKeys.masterKey!.setDirectVerified(true);
    for (final d in bobKeys.deviceKeys.values) {
      d.setDirectVerified(true);
    }
    final mx = room.matrixRoom;
    expect(E2eeTrustResolver.forRoom(mx), E2eeTrust.unverified,
        reason: 'account 3 is not verified');

    // Lazy loading: account 3's membership is not known locally yet.
    mx.states[matrix.EventTypes.RoomMember]!.remove(_carol);
    expect(mx.summary.mJoinedMemberCount, 3);
    expect(mx.participantListComplete, isFalse,
        reason: 'the SDK knows the list is incomplete');

    expect(E2eeTrustResolver.forRoom(mx), isNot(E2eeTrust.verified),
        reason: 'an unverified member is in the room: the shield must not '
            'claim every key is known to be theirs');
  });
}
