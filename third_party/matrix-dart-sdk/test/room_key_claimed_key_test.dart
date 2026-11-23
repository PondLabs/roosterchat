// ROOSTER: the Ed25519 key an `m.room_key` claims comes from the sender's
// device whose Curve25519 key is the Olm session's, never from a device the
// sender names in the content (`requesting_device_id`) nor from claimed keys
// the sender writes there. The same claim is kept in the database, used after
// a reload, sent in `m.forwarded_room_key` and uploaded to the key backup.

import 'dart:convert';

import 'package:canonical_json/canonical_json.dart';
import 'package:test/test.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/session_key.dart';
import 'package:matrix/matrix.dart';
import 'fake_client.dart';
import 'fake_database.dart';

const _otherUser = '@othertest:fakeServer.notExisting';
// A verified device of the other user, the one a forged room key names.
const _victimDevice = 'VICTIMDEV';
const _roomId = '!726s6s6q:example.com';

void main() {
  group('m.room_key claimed Ed25519 key', tags: 'olm', () {
    Logs().level = Level.error;

    late Client client;
    // The fake server [client] talks to: each new FakeMatrixApi becomes
    // `currentApi`, whose calls `calledEndpoints` lists.
    late FakeMatrixApi clientApi;
    late String victimCurve;
    late String victimEd;
    final senders = <Client>[];

    setUp(() async {
      // A fresh client per test: the fake server hands out the same one-time
      // key, which the first inbound Olm session uses up.
      client = await getClient();
      clientApi = FakeMatrixApi.currentApi!;
      await client.abortSync();

      // The verified device as `/keys/query` gave it, with the seen-keys
      // bookkeeping `/keys/query` does.
      final victim = vod.Account();
      victimCurve = victim.identityKeys.curve25519.toBase64();
      victimEd = victim.identityKeys.ed25519.toBase64();
      final unsigned = <String, Object?>{
        'algorithms': [
          AlgorithmTypes.olmV1Curve25519AesSha2,
          AlgorithmTypes.megolmV1AesSha2,
        ],
        'device_id': _victimDevice,
        'keys': {
          'curve25519:$_victimDevice': victimCurve,
          'ed25519:$_victimDevice': victimEd,
        },
        'user_id': _otherUser,
      };
      final signature =
          victim.sign(String.fromCharCodes(canonicalJson.encode(unsigned)));
      final known = DeviceKeys.fromJson(
        {
          ...unsigned,
          'signatures': {
            _otherUser: {'ed25519:$_victimDevice': signature.toBase64()},
          },
        },
        client,
      );
      final list = client.userDeviceKeys[_otherUser] ??=
          DeviceKeysList(_otherUser, client);
      list.deviceKeys[_victimDevice] = known;
      await client.database.storeUserDeviceKey(
        _otherUser,
        _victimDevice,
        json.encode(known.toJson()),
        false,
        false,
        DateTime.now().millisecondsSinceEpoch,
      );
      await client.database
          .addSeenDeviceId(_otherUser, _victimDevice, victimCurve + victimEd);
      await client.database.addSeenPublicKey(victimEd, _victimDevice);
      await client.database.addSeenPublicKey(victimCurve, _victimDevice);
      await known.setVerified(true, false);
      expect(known.verified, true);
    });

    tearDown(() async {
      for (final sender in senders) {
        await sender.dispose(closeDatabase: true);
      }
      senders.clear();
      await client.dispose(closeDatabase: true);
    });

    /// A real client of the other user with fresh keys and [deviceId].
    Future<Client> senderClient(String deviceId) async {
      final sender = Client(
        'sender$deviceId',
        httpClient: FakeMatrixApi(),
        database: await getDatabase(),
      );
      senders.add(sender);
      await sender.checkHomeserver(
        Uri.parse('https://fakeserver.notexisting'),
        checkWellKnown: false,
      );
      await sender.init(
        newToken: 'abc',
        newUserID: _otherUser,
        newHomeserver: sender.homeserver,
        newDeviceName: 'Sender',
        newDeviceID: deviceId,
      );
      await sender.abortSync();
      FakeMatrixApi.client = client;
      return sender;
    }

    /// [c]'s device keys, signed by it (an unsigned device is blocked).
    DeviceKeys deviceOf(Client c) => DeviceKeys.fromJson(
          c.encryption!.olmManager.signJson({
            'user_id': c.userID,
            'device_id': c.deviceID,
            'algorithms': [
              AlgorithmTypes.olmV1Curve25519AesSha2,
              AlgorithmTypes.megolmV1AesSha2,
            ],
            'keys': {
              'curve25519:${c.deviceID}': c.identityKey,
              'ed25519:${c.deviceID}': c.fingerprintKey,
            },
          }),
          client,
        );

    /// [sender] sends an `m.room_key` to [client] over Olm, by the normal
    /// send path, with [extra] in its content; [client] takes it in.
    Future<String> sendRoomKey(
      Client sender, [
      Map<String, Object?> extra = const {},
    ]) async {
      final group = vod.GroupSession();
      final payload = await sender.encryption!.encryptToDeviceMessage(
        [deviceOf(client)],
        EventTypes.RoomKey,
        {
          'algorithm': AlgorithmTypes.megolmV1AesSha2,
          'room_id': _roomId,
          'session_id': group.sessionId,
          'session_key': group.sessionKey,
          ...extra,
        },
      );
      final decrypted =
          await client.encryption!.olmManager.decryptToDeviceEvent(
        ToDeviceEvent(
          sender: _otherUser,
          type: EventTypes.Encrypted,
          content: payload[client.userID]![client.deviceID]!,
        ),
      );
      expect(decrypted.type, EventTypes.RoomKey);
      await client.encryption!.handleToDeviceEvent(decrypted);
      return group.sessionId;
    }

    /// The session as the database has it, after the cache is dropped.
    Future<SessionKey> reload(String sessionId) async {
      // Let the store started by setInboundGroupSession land.
      await Future.delayed(const Duration(milliseconds: 50));
      final keyManager = client.encryption!.keyManager;
      keyManager.clearInboundGroupSessions();
      expect(keyManager.getInboundGroupSession(_roomId, sessionId), isNull);
      final reloaded =
          await keyManager.loadInboundGroupSession(_roomId, sessionId);
      expect(reloaded, isNotNull);
      return reloaded!;
    }

    /// The content of the `m.forwarded_room_key` [client] sends to
    /// [requester] for [sessionId], read with the requester's Olm session;
    /// null if nothing is sent.
    Future<Map<String, dynamic>?> forwardTo(
      Client requester,
      String sessionId,
    ) async {
      final keyManager = client.encryption!.keyManager;
      final request = KeyManagerKeyShareRequest(
        requestId: 'request-$sessionId',
        devices: [deviceOf(requester)],
        room: client.getRoomById(_roomId)!,
        sessionId: sessionId,
      );
      keyManager.incomingShareRequests[request.requestId] = request;
      FakeMatrixApi.currentApi = clientApi;
      FakeMatrixApi.calledEndpoints.clear();
      await RoomKeyRequest.fromToDeviceEvent(
        ToDeviceEvent(
          sender: requester.userID!,
          type: EventTypes.RoomKeyRequest,
          content: {
            'action': 'request',
            'request_id': request.requestId,
            'requesting_device_id': requester.deviceID,
          },
        ),
        keyManager,
        request,
      ).forwardKey();
      expect(keyManager.incomingShareRequests, isNot(contains(request)));
      final sent = FakeMatrixApi.calledEndpoints.entries
          .where(
            (e) => e.key.startsWith(
              '/client/v3/sendToDevice/${EventTypes.Encrypted}/',
            ),
          )
          .expand((e) => e.value)
          .toList();
      if (sent.isEmpty) return null;
      expect(sent, hasLength(1));
      final message = (json.decode(sent.single)['messages'][requester.userID]
          [requester.deviceID]) as Map<String, dynamic>;
      expect(message['sender_key'], client.identityKey);
      final cipher = message['ciphertext'][requester.identityKey];
      final sessions = await requester.encryption!.olmManager
          .getOlmSessions(client.identityKey);
      for (final session in sessions) {
        try {
          final plain = json.decode(
            session.session!.decrypt(
              messageType: cipher['type'],
              ciphertext: cipher['body'],
            ),
          );
          expect(plain['type'], EventTypes.ForwardedRoomKey);
          return (plain['content'] as Map).cast<String, dynamic>();
        } catch (_) {
          continue;
        }
      }
      fail('the forwarded key could not be decrypted by the requester');
    }

    /// The `sender_claimed_keys` the key backup upload carries for
    /// [sessionId].
    Future<Object?> backedUpClaim(String sessionId) async {
      final stored = (await client.database.getInboundGroupSessionsToUpload())
          .where((s) => s.roomId == _roomId && s.sessionId == sessionId)
          .single;
      final backupKey = vod.PkDecryption();
      final roomKeys = generateUploadKeysImplementation(
        GenerateUploadKeysArgs(
          pubkey: backupKey.publicKey,
          dbSessions: [
            DbInboundGroupSessionBundle(dbSession: stored, verified: false),
          ],
          userId: client.userID!,
        ),
      );
      final data = roomKeys.rooms[_roomId]!.sessions[sessionId]!.sessionData;
      final decrypted = json.decode(
        backupKey.decrypt(
          vod.PkMessage.fromBase64(
            ciphertext: data['ciphertext'] as String,
            mac: data['mac'] as String,
            ephemeralKey: data['ephemeral'] as String,
          ),
        ),
      );
      return decrypted['sender_claimed_keys'];
    }

    Future<void> expectVictimUntouched() async {
      final known =
          client.userDeviceKeys[_otherUser]!.deviceKeys[_victimDevice]!;
      expect(known.curve25519Key, victimCurve);
      expect(known.ed25519Key, victimEd);
      expect(known.verified, true);
      final stored =
          (await client.database.getUserDeviceKeys(client))[_otherUser]!
              .deviceKeys[_victimDevice]!;
      expect(stored.curve25519Key, victimCurve);
      expect(stored.ed25519Key, victimEd);
    }

    test(
      'over an Olm session that is not the named device\'s, no key is claimed',
      () async {
        // The victim's device id with the attacker's own keys: OlmManager
        // ignores its sender_device_keys (a known device with other keys),
        // so the Olm session maps to no device.
        final attacker = await senderClient(_victimDevice);
        expect(attacker.identityKey, isNot(victimCurve));
        final sessionId = await sendRoomKey(attacker, {
          'requesting_device_id': _victimDevice,
          'sender_claimed_ed25519_key': victimEd,
          'sender_claimed_keys': {'ed25519': victimEd},
        });

        final session = client.encryption!.keyManager
            .getInboundGroupSession(_roomId, sessionId)!;
        expect(session.senderKey, attacker.identityKey);
        expect(
          client.getUserDeviceKeysByCurve25519Key(session.senderKey),
          null,
        );
        expect(session.senderClaimedKeys, isEmpty);
        expect(session.content, isNot(contains('sender_claimed_ed25519_key')));
        expect(session.content, isNot(contains('sender_claimed_keys')));

        final reloaded = await reload(sessionId);
        expect(reloaded.senderKey, attacker.identityKey);
        expect(reloaded.senderClaimedKeys, isEmpty);
        expect(reloaded.senderClaimedKeys.values, isNot(contains(victimEd)));
        await expectVictimUntouched();

        // A key that claims no sender is not forwarded: neither the victim's
        // key nor ours goes out with it.
        expect(await forwardTo(attacker, sessionId), isNull);
        expect(await backedUpClaim(sessionId), isEmpty);
      },
    );

    test(
      'over the Olm session of another device of the same user, that '
      'device\'s key is claimed, not the named one\'s',
      () async {
        // An attacker device of its own (its sender_device_keys are taken in,
        // unverified) naming the verified device.
        final attacker = await senderClient('ATTACKERDEV');
        final sessionId = await sendRoomKey(attacker, {
          'requesting_device_id': _victimDevice,
          'sender_claimed_ed25519_key': victimEd,
        });
        final ingested =
            client.userDeviceKeys[_otherUser]!.deviceKeys['ATTACKERDEV']!;
        expect(ingested.curve25519Key, attacker.identityKey);
        expect(ingested.verified, false);

        final claim = {'ed25519': attacker.fingerprintKey};
        expect(
          client.encryption!.keyManager
              .getInboundGroupSession(_roomId, sessionId)!
              .senderClaimedKeys,
          claim,
        );
        final reloaded = await reload(sessionId);
        expect(reloaded.senderClaimedKeys, claim);
        await expectVictimUntouched();

        final forwarded = await forwardTo(attacker, sessionId);
        expect(
          forwarded!['sender_claimed_ed25519_key'],
          attacker.fingerprintKey,
        );
        expect(forwarded['sender_key'], attacker.identityKey);
        expect(await backedUpClaim(sessionId), claim);
      },
    );

    test(
      'from a known device, its own key is claimed and it stays trusted',
      () async {
        final sender = await senderClient('LEGITDEV');
        final device = DeviceKeys.fromJson(
          sender.encryption!.olmManager.signJson({
            'algorithms': [
              AlgorithmTypes.olmV1Curve25519AesSha2,
              AlgorithmTypes.megolmV1AesSha2,
            ],
            'device_id': 'LEGITDEV',
            'keys': {
              'curve25519:LEGITDEV': sender.identityKey,
              'ed25519:LEGITDEV': sender.fingerprintKey,
            },
            'user_id': _otherUser,
          }),
          client,
        );
        expect(device.isValid, true);
        client.userDeviceKeys[_otherUser]!.deviceKeys['LEGITDEV'] = device;
        await device.setVerified(true, false);

        final sessionId = await sendRoomKey(sender);
        final claim = {'ed25519': sender.fingerprintKey};
        final session = client.encryption!.keyManager
            .getInboundGroupSession(_roomId, sessionId)!;
        expect(session.senderKey, sender.identityKey);
        expect(session.senderClaimedKeys, claim);

        final reloaded = await reload(sessionId);
        expect(reloaded.senderKey, sender.identityKey);
        expect(reloaded.senderClaimedKeys, claim);
        final owner =
            client.getUserDeviceKeysByCurve25519Key(reloaded.senderKey);
        expect(owner?.deviceId, 'LEGITDEV');
        expect(owner?.ed25519Key, reloaded.senderClaimedKeys['ed25519']);
        expect(owner?.verified, true);
        await expectVictimUntouched();

        final forwarded = await forwardTo(sender, sessionId);
        expect(forwarded!['sender_claimed_ed25519_key'], sender.fingerprintKey);
        expect(forwarded['sender_key'], sender.identityKey);
        expect(await backedUpClaim(sessionId), claim);
      },
    );
  });
}
