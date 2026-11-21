// ROOSTER: Olm `sender_device_keys` (Matrix v1.15, MSC4147) and the
// `m.key_backup` account data (Matrix v1.19, MSC4287).

import 'dart:convert';

import 'package:canonical_json/canonical_json.dart';
import 'package:test/test.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/json_signature_check_extension.dart';
import 'package:matrix/encryption/utils/pickle_key.dart';
import 'package:matrix/matrix.dart';
import 'fake_client.dart';
import 'fake_database.dart';

const _otherUser = '@othertest:fakeServer.notExisting';
// Not FOXDEVICE: the fake server's /keys/query has other keys under that id.
const _otherDevice = 'SENDERKEYS';

void main() {
  group('Olm sender_device_keys (MSC4147)', tags: 'olm', () {
    Logs().level = Level.error;

    late Client client;
    late Client otherClient;
    late DeviceKeys device;
    // A copy of the recipient's account made before anything reached it: it
    // reads the first message's plaintext without touching the client.
    late vod.Account copy;
    vod.Session? copySession;

    setUpAll(() async {
      client = await getClient();
      await client.abortSync();
      copy = vod.Account.fromPickleEncrypted(
        pickle: client.encryption!.olmManager.pickledOlmAccount!,
        pickleKey: client.userID!.toPickleKey(),
      );
      otherClient = Client(
        'othertestclient',
        httpClient: FakeMatrixApi(),
        database: await getDatabase(),
      );
      await otherClient.checkHomeserver(
        Uri.parse('https://fakeserver.notexisting'),
        checkWellKnown: false,
      );
      await otherClient.init(
        newToken: 'abc',
        newUserID: _otherUser,
        newHomeserver: otherClient.homeserver,
        newDeviceName: 'Text Matrix Client',
        newDeviceID: _otherDevice,
      );
      await otherClient.abortSync();
      FakeMatrixApi.client = client;
      device = DeviceKeys.fromJson(
        {
          'user_id': client.userID,
          'device_id': client.deviceID,
          'algorithms': [
            AlgorithmTypes.olmV1Curve25519AesSha2,
            AlgorithmTypes.megolmV1AesSha2,
          ],
          'keys': {
            'curve25519:${client.deviceID}': client.identityKey,
            'ed25519:${client.deviceID}': client.fingerprintKey,
          },
        },
        client,
      );
    });

    tearDownAll(() async {
      await client.dispose(closeDatabase: true);
      await otherClient.dispose(closeDatabase: true);
    });

    ToDeviceEvent toDevice(Map<String, dynamic> payload) => ToDeviceEvent(
          sender: _otherUser,
          type: EventTypes.Encrypted,
          content: payload[client.userID][client.deviceID],
        );

    /// What the copy of the recipient's account reads in [event].
    Map<String, dynamic> plaintextOf(ToDeviceEvent event) {
      final cipher = (event.content['ciphertext'] as Map)[client.identityKey];
      final String text;
      if (copySession == null) {
        final result = copy.createInboundSession(
          theirIdentityKey:
              vod.Curve25519PublicKey.fromBase64(otherClient.identityKey),
          preKeyMessageBase64: cipher['body'],
        );
        copySession = result.session;
        text = result.plaintext;
      } else {
        text = copySession!.decrypt(
          messageType: cipher['type'],
          ciphertext: cipher['body'],
        );
      }
      return json.decode(text);
    }

    Map<String, Object?> signedBy(vod.Account account, Map<String, Object?> j) {
      final unsigned = Map<String, Object?>.from(j)..remove('signatures');
      final sig =
          account.sign(String.fromCharCodes(canonicalJson.encode(unsigned)));
      return {
        ...unsigned,
        'signatures': {
          j['user_id']: {'ed25519:${j['device_id']}': sig.toBase64()},
        },
      };
    }

    /// An Olm message from [otherClient] whose plaintext the test writes.
    Future<ToDeviceEvent> craft(Map<String, Object?> plaintext) async {
      final olm = otherClient.encryption!.olmManager;
      final sessions = await olm.getOlmSessions(client.identityKey);
      final result = sessions.first.session!.encrypt(json.encode(plaintext));
      await olm.storeOlmSession(sessions.first);
      return ToDeviceEvent(
        sender: _otherUser,
        type: EventTypes.Encrypted,
        content: {
          'algorithm': AlgorithmTypes.olmV1Curve25519AesSha2,
          'sender_key': otherClient.identityKey,
          'ciphertext': {
            client.identityKey: {
              'type': result.messageType,
              'body': result.ciphertext,
            },
          },
        },
      );
    }

    Map<String, Object?> plaintextWith(
      Map<String, Object?> senderDeviceKeys, {
      String? claimedEd25519,
    }) =>
        {
          'type': 'm.to_device',
          'content': {'hello': 'forged'},
          'sender': _otherUser,
          'keys': {'ed25519': claimedEd25519 ?? otherClient.fingerprintKey},
          'recipient': client.userID,
          'recipient_keys': {'ed25519': client.fingerprintKey},
          'sender_device_keys': senderDeviceKeys,
        };

    Map<String, Object?> realKeys() =>
        otherClient.encryption!.olmManager.signJson({
          'algorithms': [
            AlgorithmTypes.olmV1Curve25519AesSha2,
            AlgorithmTypes.megolmV1AesSha2,
          ],
          'device_id': _otherDevice,
          'keys': {
            'curve25519:$_otherDevice': otherClient.identityKey,
            'ed25519:$_otherDevice': otherClient.fingerprintKey,
          },
          'user_id': _otherUser,
        });

    Future<bool> storedInDatabase() async =>
        (await client.database.getUserDeviceKeys(client))[_otherUser]
            ?.deviceKeys
            .containsKey(_otherDevice) ??
        false;

    Future<void> expectRejected(ToDeviceEvent event, String why) async {
      // [Encryption.decryptToDeviceEvent] logs this and hands the event on
      // still encrypted: its content never reaches the app.
      await expectLater(
        client.encryption!.olmManager.decryptToDeviceEvent(event),
        throwsA(
          isA<DecryptException>()
              .having((e) => e.libolmMessage, 'reason', contains(why)),
        ),
      );
    }

    test('the payload carries our signed device keys', () async {
      final payload = await otherClient.encryption!.encryptToDeviceMessage(
        [device],
        'm.to_device',
        {'hello': 'foxies'},
      );
      final event = toDevice(payload);
      final plain = plaintextOf(event);
      final keys = (plain['sender_device_keys'] as Map).cast<String, Object?>();
      expect(keys['user_id'], _otherUser);
      expect(keys['device_id'], _otherDevice);
      expect(keys['keys'], {
        'curve25519:$_otherDevice': otherClient.identityKey,
        'ed25519:$_otherDevice': otherClient.fingerprintKey,
      });
      expect(keys.containsKey('unsigned'), false);
      expect(
        Map<String, dynamic>.from(keys).checkJsonSignature(
          otherClient.fingerprintKey,
          _otherUser,
          _otherDevice,
        ),
        true,
      );

      // A device the recipient never queried: nothing known before.
      expect(client.userDeviceKeys[_otherUser]?.deviceKeys[_otherDevice], null);
      expect(await storedInDatabase(), false);

      final decrypted = await client.encryption!.decryptToDeviceEvent(event);
      expect(decrypted.content['hello'], 'foxies');
      final ingested =
          client.userDeviceKeys[_otherUser]!.deviceKeys[_otherDevice]!;
      expect(ingested.ed25519Key, otherClient.fingerprintKey);
      expect(ingested.curve25519Key, otherClient.identityKey);
      expect(ingested.selfSigned, true);
      expect(ingested.verified, false);
      expect(client.userDeviceKeys[_otherUser]!.outdated, true);
      expect(await storedInDatabase(), true);
      expect(
        client.getUserDeviceKeysByCurve25519Key(otherClient.identityKey),
        ingested,
      );
    });

    group('forged sender_device_keys are rejected', () {
      late Map<String, dynamic> before;
      late Set<String> devicesBefore;

      setUp(() async {
        devicesBefore =
            client.userDeviceKeys[_otherUser]!.deviceKeys.keys.toSet();
        before = (await client.database.getUserDeviceKeys(client))[_otherUser]!
            .deviceKeys[_otherDevice]!
            .toJson();
      });

      Future<void> expectUnchanged() async {
        final known =
            client.userDeviceKeys[_otherUser]!.deviceKeys[_otherDevice]!;
        expect(known.toJson(), before);
        final stored =
            (await client.database.getUserDeviceKeys(client))[_otherUser]!
                .deviceKeys[_otherDevice]!;
        expect(stored.toJson(), before);
        expect(
          client.userDeviceKeys[_otherUser]!.deviceKeys.keys.toSet(),
          devicesBefore,
        );
      }

      test('a Curve25519 key that is not the Olm session\'s', () async {
        final keys = realKeys();
        final attacker = vod.Account();
        final forged = otherClient.encryption!.olmManager.signJson({
          ...keys..remove('signatures'),
          'keys': {
            'curve25519:$_otherDevice':
                attacker.identityKeys.curve25519.toBase64(),
            'ed25519:$_otherDevice': otherClient.fingerprintKey,
          },
        });
        await expectRejected(
          await craft(plaintextWith(forged)),
          'Curve25519 key is not the Olm session',
        );
        await expectUnchanged();
      });

      test('an Ed25519 key that is not the payload\'s', () async {
        final attacker = vod.Account();
        final forged = signedBy(attacker, {
          'algorithms': [AlgorithmTypes.olmV1Curve25519AesSha2],
          'device_id': _otherDevice,
          'keys': {
            'curve25519:$_otherDevice': otherClient.identityKey,
            'ed25519:$_otherDevice': attacker.identityKeys.ed25519.toBase64(),
          },
          'user_id': _otherUser,
        });
        await expectRejected(
          await craft(plaintextWith(forged)),
          'Ed25519 key is not the one the payload claims',
        );
        await expectUnchanged();
      });

      test('a bad signature', () async {
        final forged = realKeys()
          ..['algorithms'] = [AlgorithmTypes.olmV1Curve25519AesSha2];
        await expectRejected(
          await craft(plaintextWith(forged)),
          'bad signature',
        );
        await expectUnchanged();
      });

      test('another user\'s keys', () async {
        final keys = realKeys()..remove('signatures');
        final forged = otherClient.encryption!.olmManager
            .signJson({...keys, 'user_id': '@mallory:fakeServer.notExisting'});
        await expectRejected(
          await craft(plaintextWith(forged)),
          'not the device keys of the sender',
        );
        await expectUnchanged();
      });

      test('a known device id with other keys is not used', () async {
        // Consistent with itself (the claimed Ed25519 key is the attacker's,
        // and signs it), but the device is known with other keys: the event
        // is handled as without MSC4147, and the known device stays.
        final attacker = vod.Account();
        final attackerEd = attacker.identityKeys.ed25519.toBase64();
        final forged = signedBy(attacker, {
          'algorithms': [AlgorithmTypes.olmV1Curve25519AesSha2],
          'device_id': _otherDevice,
          'keys': {
            'curve25519:$_otherDevice': otherClient.identityKey,
            'ed25519:$_otherDevice': attackerEd,
          },
          'user_id': _otherUser,
        });
        final decrypted =
            await client.encryption!.olmManager.decryptToDeviceEvent(
          await craft(plaintextWith(forged, claimedEd25519: attackerEd)),
        );
        expect(decrypted.content['hello'], 'forged');
        await expectUnchanged();
      });

      test('keys that are not an object', () async {
        await expectRejected(
          await craft(plaintextWith({'keys': 'nope'})),
          'not the device keys of the sender',
        );
        await expectUnchanged();
      });
    });

    test('a valid known device still decrypts', () async {
      final payload = await otherClient.encryption!.encryptToDeviceMessage(
        [device],
        'm.to_device',
        {'hello': 'again'},
      );
      final decrypted =
          await client.encryption!.decryptToDeviceEvent(toDevice(payload));
      expect(decrypted.content['hello'], 'again');
    });
  });
}
