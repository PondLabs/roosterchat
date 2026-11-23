// ROOSTER: a Megolm session that reaches setInboundGroupSession is compared
// with the one the database keeps, not only with the one in memory. After a
// restart nothing is in memory, and upstream let a session from the key
// backup or a forwarded key that starts later replace a stored one that
// starts at index 0, so earlier messages stopped decrypting.

import 'dart:convert';

import 'package:test/test.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/session_key.dart';
import 'package:matrix/matrix.dart';
import 'fake_client.dart';

// A room of the fake sync where @alice:example.com has the device with
// [_aliceCurve], which a key request is sent to.
const _roomId = '!726s6s6q:example.com';
const _aliceCurve = 'L+4+JCl8MD63dgo8z5Ta+9QAHXiANyOVSfgbHA5d3H8';
const _aliceEd = 'ub2Jr7MHkqyvjH7Fm7FRNq8tHZxDMYFtsohMOiFiwjg';
// The Curve25519 key of the session's creator.
const _senderKey = 'JBG7ZaPn54OBC7TuIEiylW3BZ+7WcGQhFBPB9pogbAg';

void main() {
  group('setInboundGroupSession keeps the better stored session', tags: 'olm',
      () {
    Logs().level = Level.error;

    late Client client;
    late KeyManager keyManager;
    late vod.GroupSession outbound;
    late vod.InboundGroupSession inbound;
    late String sessionId;
    // The session key its sender's `m.room_key` carries, from index 0.
    late String roomKey;
    // A message at index 0, which only a session from index 0 decrypts.
    late Event firstMessage;

    setUp(() async {
      client = await getClient();
      await client.abortSync();
      keyManager = client.encryption!.keyManager;

      outbound = vod.GroupSession();
      inbound = vod.InboundGroupSession(outbound.sessionKey);
      sessionId = outbound.sessionId;
      roomKey = outbound.sessionKey;
      firstMessage = Event(
        senderId: '@alice:example.com',
        type: EventTypes.Encrypted,
        room: client.getRoomById(_roomId)!,
        eventId: '\$first',
        originServerTs: DateTime.now(),
        content: {
          'algorithm': AlgorithmTypes.megolmV1AesSha2,
          'ciphertext': outbound.encrypt(
            json.encode({
              'type': 'm.room.message',
              'content': {'msgtype': 'm.text', 'body': 'first'},
            }),
          ),
          'device_id': 'ALICEDEVICE',
          'sender_key': _senderKey,
          'session_id': sessionId,
        },
      );
      // Later messages move the session on, so it can be exported from 1, 2.
      outbound.encrypt('second');
      outbound.encrypt('third');
    });

    tearDown(() async {
      await client.dispose(closeDatabase: true);
    });

    Map<String, dynamic> forwardedContent(int index) => {
          'algorithm': AlgorithmTypes.megolmV1AesSha2,
          'room_id': _roomId,
          'session_id': sessionId,
          'session_key': inbound.exportAt(index),
          'sender_key': _senderKey,
          'forwarding_curve25519_key_chain': <String>[],
          'sender_claimed_ed25519_key': _aliceEd,
        };

    /// Stores the session from its sender (`m.room_key`, index 0).
    Future<void> storeFromSender() => keyManager.setInboundGroupSession(
          _roomId,
          sessionId,
          _senderKey,
          {
            'algorithm': AlgorithmTypes.megolmV1AesSha2,
            'room_id': _roomId,
            'session_id': sessionId,
            'session_key': roomKey,
          },
        );

    Future<SessionKey?> stored() async {
      final entry = await client.database.getInboundGroupSession(
        _roomId,
        sessionId,
      );
      return entry == null ? null : SessionKey.fromDb(entry, client.userID!);
    }

    /// What a restart leaves: the database, nothing in memory.
    void restart() {
      keyManager.clearInboundGroupSessions();
      expect(keyManager.getInboundGroupSession(_roomId, sessionId), isNull);
    }

    Future<String> decryptFirstMessage() async {
      restart();
      final decrypted = await client.encryption!.decryptRoomEvent(firstMessage);
      return decrypted.type == EventTypes.Message
          ? decrypted.content['body'] as String
          : 'undecryptable';
    }

    /// The online key backup's answer with the session from [index].
    Future<RoomKeys> backupFrom(int index) async {
      final info = await keyManager.getRoomKeysBackupInfo();
      final encryption = vod.PkEncryption.fromPublicKey(
        vod.Curve25519PublicKey.fromBase64(
          info.authData['public_key'] as String,
        ),
      );
      final (ciphertext, mac, ephemeral) = encryption
          .encrypt(
            json.encode({
              'algorithm': AlgorithmTypes.megolmV1AesSha2,
              'forwarding_curve25519_key_chain': <String>[],
              'sender_key': _senderKey,
              'sender_claimed_keys': {'ed25519': _aliceEd},
              'session_key': inbound.exportAt(index),
            }),
          )
          .toBase64();
      return RoomKeys(
        rooms: {
          _roomId: RoomKeyBackup(
            sessions: {
              sessionId: KeyBackupData(
                firstMessageIndex: index,
                forwardedCount: 0,
                isVerified: false,
                sessionData: {
                  'ephemeral': ephemeral,
                  'ciphertext': ciphertext,
                  'mac': mac,
                },
              ),
            },
          ),
        },
      );
    }

    Future<void> unlockBackup() async {
      final handle = client.encryption!.ssss.open();
      await handle.unlock(recoveryKey: ssssKey);
      await handle.maybeCacheAll();
      expect(await keyManager.isCached(), true);
    }

    /// An `m.forwarded_room_key` from Alice's device for the session from
    /// [index], answering a key request sent to her.
    Future<void> receiveForwarded(int index) async {
      await keyManager.request(
        client.getRoomById(_roomId)!,
        sessionId,
        _senderKey,
        tryOnlineBackup: false,
      );
      await keyManager.handleToDeviceEvent(
        ToDeviceEvent(
          sender: '@alice:example.com',
          type: EventTypes.ForwardedRoomKey,
          content: forwardedContent(index),
          encryptedContent: {'sender_key': _aliceCurve},
        ),
      );
    }

    test('the key backup does not replace a stored session that starts earlier',
        () async {
      await unlockBackup();
      await storeFromSender();
      restart();

      await keyManager.loadFromResponse(await backupFrom(1));

      expect((await stored())?.inboundGroupSession?.firstKnownIndex, 0);
      expect(await decryptFirstMessage(), 'first');
    });

    test(
        'a forwarded key does not replace a stored session that starts earlier',
        () async {
      await storeFromSender();
      restart();

      await receiveForwarded(1);

      expect((await stored())?.inboundGroupSession?.firstKnownIndex, 0);
      expect(await decryptFirstMessage(), 'first');
    });

    test('a forwarded key that starts earlier replaces the stored session',
        () async {
      await keyManager.setInboundGroupSession(
        _roomId,
        sessionId,
        _senderKey,
        forwardedContent(2),
        forwarded: true,
      );
      expect(await decryptFirstMessage(), 'undecryptable');
      restart();

      await receiveForwarded(0);

      expect(
        keyManager
            .getInboundGroupSession(_roomId, sessionId)
            ?.inboundGroupSession
            ?.firstKnownIndex,
        0,
      );
      expect((await stored())?.inboundGroupSession?.firstKnownIndex, 0);
      expect(await decryptFirstMessage(), 'first');
    });

    test('the key backup stores a session the database does not have',
        () async {
      await unlockBackup();
      expect(await stored(), isNull);

      await keyManager.loadFromResponse(await backupFrom(0));

      expect(
        keyManager.getInboundGroupSession(_roomId, sessionId)?.sessionId,
        sessionId,
      );
      expect((await stored())?.inboundGroupSession?.firstKnownIndex, 0);
      expect(await decryptFirstMessage(), 'first');
    });

    test('a forwarded key stores a session the database does not have',
        () async {
      expect(await stored(), isNull);

      await receiveForwarded(1);

      expect((await stored())?.inboundGroupSession?.firstKnownIndex, 1);
    });

    test('of two calls at once, the session that starts earlier stays',
        () async {
      await keyManager.setInboundGroupSession(
        _roomId,
        sessionId,
        _senderKey,
        forwardedContent(2),
        forwarded: true,
      );
      restart();

      // Both read the database before either writes; the second must still
      // see the first one's session in memory.
      await Future.wait([
        keyManager.setInboundGroupSession(
          _roomId,
          sessionId,
          _senderKey,
          forwardedContent(0),
          forwarded: true,
        ),
        keyManager.setInboundGroupSession(
          _roomId,
          sessionId,
          _senderKey,
          forwardedContent(1),
          forwarded: true,
        ),
      ]);

      expect(
        keyManager
            .getInboundGroupSession(_roomId, sessionId)
            ?.inboundGroupSession
            ?.firstKnownIndex,
        0,
      );
      expect((await stored())?.inboundGroupSession?.firstKnownIndex, 0);
    });
  });
}
