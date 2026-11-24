// ROOSTER: sessions stored before Rooster took an `m.room_key`'s claimed
// Ed25519 key from its Olm session kept the key of the device the sender
// named in `requesting_device_id` in their content, with no claimed keys of
// their own. The first start on such a database proves the claim from the
// Olm session's Curve25519 key or drops it, once, and deletes nothing.

import 'dart:convert';

import 'package:canonical_json/canonical_json.dart';
import 'package:test/test.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/pickle_key.dart';
import 'package:matrix/encryption/utils/session_key.dart';
import 'package:matrix/encryption/utils/stored_inbound_group_session.dart';
import 'package:matrix/matrix.dart';
import 'fake_client.dart';
import 'fake_database.dart';

const _userId = '@test:fakeServer.notExisting';
// A member of the room, so the client keeps tracking their devices.
const _sender = '@alice:example.com';
const _roomId = '!726s6s6q:example.com';

/// A device of [_sender], signed by its own key, as `/keys/query` gives it.
class _Device {
  final String id;
  final vod.Account account = vod.Account();
  final String? curveOverride;
  _Device(this.id, {this.curveOverride});

  String get curve =>
      curveOverride ?? account.identityKeys.curve25519.toBase64();
  String get ed => account.identityKeys.ed25519.toBase64();

  Map<String, Object?> get json {
    final unsigned = <String, Object?>{
      'algorithms': [
        AlgorithmTypes.olmV1Curve25519AesSha2,
        AlgorithmTypes.megolmV1AesSha2,
      ],
      'device_id': id,
      'keys': {'curve25519:$id': curve, 'ed25519:$id': ed},
      'user_id': _sender,
    };
    final signature =
        account.sign(String.fromCharCodes(canonicalJson.encode(unsigned)));
    return {
      ...unsigned,
      'signatures': {
        _sender: {'ed25519:$id': signature.toBase64()},
      },
    };
  }
}

void main() {
  group('claimed keys stored before T3.1b', tags: 'olm', () {
    Logs().level = Level.error;

    late DatabaseApi database;
    late _Device victim; // verified, named in `requesting_device_id`
    late _Device legit; // verified, holds the Curve25519 key of an Olm session
    final groups = <String, vod.GroupSession>{};
    // Per session, each message's ciphertext and timestamp, kept so that the
    // same event is decrypted again unchanged (the replay check).
    final sent = <String, Map<String, (String, int)>>{};
    Client? client;
    // The sender's devices, as `/keys/query` gives them on the first sync.
    final served = <_Device>[];

    /// [device] as the database had it before the update: verified.
    Future<void> knowDevice(_Device device) async {
      served.add(device);
      await database.storeUserDeviceKey(
        _sender,
        device.id,
        json.encode(device.json),
        true,
        false,
        DateTime.now().millisecondsSinceEpoch,
      );
      await database.storeUserDeviceKeysInfo(_sender, false);
    }

    setUp(() async {
      vodInit ??= vod.init(
        wasmPath: './pkg/',
        libraryPath: './rust/target/debug/',
      );
      await vodInit;
      database = await getDatabase();
      victim = _Device('VICTIMDEV');
      legit = _Device('LEGITDEV');
      served.clear();
      await knowDevice(victim);
      await knowDevice(legit);
      groups.clear();
      sent.clear();
    });

    tearDown(() async {
      await client?.dispose(closeDatabase: false);
      client = null;
      await database.close();
    });

    (String, int) encrypt(String sessionId, String body) =>
        (sent[sessionId] ??= {})[body] ??= (
          groups[sessionId]!.encrypt(
            json.encode({
              'type': EventTypes.Message,
              'content': {'msgtype': MessageTypes.Text, 'body': body},
              'room_id': _roomId,
            }),
          ),
          1000 + sent[sessionId]!.length,
        );

    /// A session as an `m.room_key` over an Olm session with [senderKey] left
    /// it, with [claim] (the named device's key) in the content and
    /// [column] as its own claimed keys.
    Future<String> storeOldSession(
      String senderKey, {
      String? claim,
      Map<String, String> column = const {},
    }) async {
      final group = vod.GroupSession();
      groups[group.sessionId] = group;
      final inbound = vod.InboundGroupSession(group.sessionKey);
      encrypt(group.sessionId, 'old'); // a message from before the update
      await database.storeInboundGroupSession(
        _roomId,
        group.sessionId,
        inbound.toPickleEncrypted(_userId.toPickleKey()),
        json.encode({
          'algorithm': AlgorithmTypes.megolmV1AesSha2,
          'room_id': _roomId,
          'session_id': group.sessionId,
          'session_key': group.sessionKey,
          'requesting_device_id': victim.id,
          if (claim != null) 'sender_claimed_ed25519_key': claim,
          if (claim != null) 'sender_claimed_keys': {'ed25519': claim},
        }),
        '{}',
        '{}',
        senderKey,
        json.encode(column),
      );
      return group.sessionId;
    }

    /// A client started on [database], up to its first sync and the
    /// migration that sync starts.
    Future<Client> start() async {
      await client?.dispose(closeDatabase: false);
      final fake = FakeMatrixApi();
      final query = fake.api['POST']!['/client/v3/keys/query']!;
      fake.api['POST']!['/client/v3/keys/query'] = (req) {
        final response = Map<String, dynamic>.of(query(req));
        response['device_keys'] = {
          ...response['device_keys'],
          _sender: {for (final d in served) d.id: d.json},
        };
        return response;
      };
      final c = client = Client(
        'testclient',
        httpClient: fake,
        database: database,
      );
      FakeMatrixApi.client = c;
      await c.checkHomeserver(
        Uri.parse('https://fakeServer.notExisting'),
        checkWellKnown: false,
      );
      await c.init(
        newToken: 'abcd',
        newUserID: _userId,
        newHomeserver: c.homeserver,
        newDeviceName: 'Text Matrix Client',
        newDeviceID: 'GHTYAJCE',
        newOlmAccount: pickledOlmAccount,
        waitForFirstSync: true,
      );
      await c.abortSync();
      final migration = c.encryption!.keyManager.claimedKeysMigration;
      expect(migration, isNotNull, reason: 'the first sync starts it');
      await migration;
      return c;
    }

    Future<StoredInboundGroupSession> stored(String sessionId) async =>
        (await database.getInboundGroupSession(_roomId, sessionId))!;

    /// A message of [sessionId]'s sender, decrypted by [c].
    Future<Event> message(Client c, String sessionId, String body) async {
      final (ciphertext, ts) = encrypt(sessionId, body);
      final decrypted = await c.encryption!.decryptRoomEvent(
        Event(
          type: EventTypes.Encrypted,
          content: {
            'algorithm': AlgorithmTypes.megolmV1AesSha2,
            'ciphertext': ciphertext,
            'session_id': sessionId,
          },
          senderId: _sender,
          eventId: '\$$sessionId-$body',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
          room: c.getRoomById(_roomId)!,
        ),
      );
      expect(decrypted.type, EventTypes.Message);
      expect(decrypted.body, body);
      return decrypted;
    }

    /// The `sender_claimed_keys` the key backup upload carries.
    Future<Object?> backedUpClaim(String sessionId) async {
      final backupKey = vod.PkDecryption();
      final roomKeys = generateUploadKeysImplementation(
        GenerateUploadKeysArgs(
          pubkey: backupKey.publicKey,
          dbSessions: [
            DbInboundGroupSessionBundle(
              dbSession: await stored(sessionId),
              verified: false,
            ),
          ],
          userId: _userId,
        ),
      );
      final data = roomKeys.rooms[_roomId]!.sessions[sessionId]!.sessionData;
      return json.decode(
        backupKey.decrypt(
          vod.PkMessage.fromBase64(
            ciphertext: data['ciphertext'] as String,
            mac: data['mac'] as String,
            ephemeralKey: data['ephemeral'] as String,
          ),
        ),
      )['sender_claimed_keys'];
    }

    void expectNoClaimInContent(Map<String, Object?> content) {
      expect(content, isNot(contains('sender_claimed_ed25519_key')));
      expect(content, isNot(contains('sender_claimed_keys')));
    }

    test('an Olm session no device is known for: the claim is dropped',
        () async {
      final attacker = vod.Account().identityKeys.curve25519.toBase64();
      final sessionId = await storeOldSession(attacker, claim: victim.ed);
      final before = await stored(sessionId);
      // Before the migration a load already ignores the content's claim.
      expect(SessionKey.fromDb(before, _userId).senderClaimedKeys, isEmpty);

      final c = await start();
      final after = await stored(sessionId);
      expect(after.pickle, before.pickle);
      expect(after.senderKey, attacker);
      expect(json.decode(after.senderClaimedKeys), isEmpty);
      expectNoClaimInContent(Event.getMapFromPayload(after.content));
      expect(SessionKey.fromDb(after, _userId).senderClaimedKeys, isEmpty);

      final event = await message(c, sessionId, 'old');
      final session =
          c.encryption!.keyManager.getInboundGroupSession(_roomId, sessionId)!;
      expect(session.senderClaimedKeys, isEmpty);
      expect(
        c.encryption!.megolmSenderTrust(event),
        MegolmSenderTrust.unverifiedOrigin,
      );
      expect(await backedUpClaim(sessionId), isEmpty);
      expect(
        c.userDeviceKeys[_sender]!.deviceKeys[victim.id]!.verified,
        true,
      );
    });

    test('an Olm session of a known device: that device\'s key is claimed',
        () async {
      final sessionId = await storeOldSession(legit.curve, claim: victim.ed);
      final c = await start();

      final claim = {'ed25519': legit.ed};
      final after = await stored(sessionId);
      expect(json.decode(after.senderClaimedKeys), claim);
      expectNoClaimInContent(Event.getMapFromPayload(after.content));

      final event = await message(c, sessionId, 'old');
      expect(
        c.encryption!.keyManager
            .getInboundGroupSession(_roomId, sessionId)!
            .senderClaimedKeys,
        claim,
      );
      expect(
        c.encryption!.megolmSenderTrust(event),
        MegolmSenderTrust.verified,
      );
      expect(await backedUpClaim(sessionId), claim);
    });

    test('a Curve25519 key two devices list proves nothing', () async {
      final copycat = _Device('COPYCAT', curveOverride: legit.curve);
      await knowDevice(copycat);
      final sessionId = await storeOldSession(legit.curve, claim: copycat.ed);
      final c = await start();
      expect(json.decode((await stored(sessionId)).senderClaimedKeys), isEmpty);
      expect(
        c.encryption!.megolmSenderTrust(await message(c, sessionId, 'old')),
        MegolmSenderTrust.unverifiedOrigin,
      );
    });

    test('a session stored with the right claim is left as it was', () async {
      final sessionId = await storeOldSession(
        legit.curve,
        claim: legit.ed,
        column: {'ed25519': legit.ed},
      );
      final before = await stored(sessionId);
      final c = await start();
      expect((await stored(sessionId)).toJson(), before.toJson());
      expect(
        c.encryption!.megolmSenderTrust(await message(c, sessionId, 'old')),
        MegolmSenderTrust.verified,
      );
    });

    test("a claim of another device than the Olm session's is not verified",
        () async {
      // Claimed keys of its own (the migration leaves it): the victim's key
      // over the Olm session of the legit device.
      final sessionId = await storeOldSession(
        legit.curve,
        column: {'ed25519': victim.ed},
      );
      final c = await start();
      expect(
        c.encryption!.megolmSenderTrust(await message(c, sessionId, 'old')),
        MegolmSenderTrust.unverifiedOrigin,
      );
    });

    test('it runs once per database and every old message still decrypts',
        () async {
      final attacker = vod.Account().identityKeys.curve25519.toBase64();
      final dropped = await storeOldSession(attacker, claim: victim.ed);
      final proven = await storeOldSession(legit.curve, claim: victim.ed);
      var c = await start();
      for (final id in [dropped, proven]) {
        await message(c, id, 'old');
        await message(c, id, 'new');
      }
      final mark = await database.getCustomCacheObject(
        KeyManager.claimedKeysMigrationCacheKey,
      );
      expect(mark?.content, {'version': 1});
      final migrated = {
        for (final id in [dropped, proven]) id: (await stored(id)).toJson(),
      };

      // A session shaped like the old ones, stored after the mark: a second
      // start leaves it in the database as it is.
      final late = await storeOldSession(attacker, claim: victim.ed);
      final lateBefore = (await stored(late)).toJson();
      c = await start();
      expect((await stored(late)).toJson(), lateBefore);
      for (final id in [dropped, proven]) {
        final now = (await stored(id)).toJson()..remove('indexes');
        expect(now, Map.of(migrated[id]!)..remove('indexes'));
        await message(c, id, 'old');
        await message(c, id, 'new');
      }
      expect(
        (await database.getAllInboundGroupSessions()).map((s) => s.sessionId),
        containsAll([dropped, proven, late]),
      );
    });
  });
}
