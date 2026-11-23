// ROOSTER: Matrix v1.19 (MSC4268), sharing a room's encrypted history on
// invite. The inviter puts the Megolm sessions the room's history visibility
// lets newcomers read in a bundle, encrypts it as an attachment, uploads it
// and sends where it is in an Olm-encrypted `m.room_key_bundle` to the
// invitee's devices it shares room keys with. The invitee takes it only from
// whoever invited it, once it joins, after checking size, hash and rooms.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:vodozemac/vodozemac.dart' as vod;

import 'package:matrix/encryption/encryption.dart';
import 'package:matrix/encryption/utils/session_key.dart';
import 'package:matrix/matrix.dart';

/// The unstable type Element sends (MSC4268), read like the stable one.
const String unstableRoomKeyBundleType = 'io.element.msc4268.room_key_bundle';

/// Marks a Megolm session whose messages newcomers may read (MSC3061): set
/// when the session starts in a room whose history visibility is `shared` or
/// `world_readable`. Only such sessions go in a bundle.
const String sharedHistoryKey = 'shared_history';

/// Whether a session started under [visibility] may be shared (MSC3061).
bool sessionHistoryIsShared(HistoryVisibility? visibility) =>
    visibility == HistoryVisibility.shared ||
    visibility == HistoryVisibility.worldReadable;

/// Whether a room under [visibility] shares its history on invite: never
/// with `joined`, nor when the room states none.
bool roomSharesHistoryOnInvite(HistoryVisibility? visibility) =>
    visibility == HistoryVisibility.shared ||
    visibility == HistoryVisibility.invited ||
    visibility == HistoryVisibility.worldReadable;

/// Why a bundle was not taken in. Nothing is imported in any of these cases.
enum RoomKeyBundleRejection {
  notEncrypted,
  untrustedDevice,
  notInvitedBySender,
  inviteNotActive,
  malformed,
  tooLarge,
  downloadFailed,
  hashMismatch,
  wrongRoom,
}

/// Keys taken in from a bundle, for the notice the app shows.
class RoomKeyBundleImport {
  final String roomId;
  final String senderId;
  final int imported;
  final int skipped;
  final DateTime when;

  RoomKeyBundleImport({
    required this.roomId,
    required this.senderId,
    required this.imported,
    required this.skipped,
    required this.when,
  });
}

class _PendingBundle {
  final String senderId;
  final String senderKey;
  final RoomKeyBundleContent content;
  final DateTime received;

  _PendingBundle(this.senderId, this.senderKey, this.content, this.received);
}

class RoomKeyBundleManager {
  final Encryption encryption;
  Client get client => encryption.client;

  /// The largest bundle taken in, checked before anything is decrypted.
  static const int defaultMaxBundleBytes = 10 * 1024 * 1024;
  int maxBundleBytes = defaultMaxBundleBytes;

  /// How long a bundle waits for us to join the room it is for.
  static const Duration pendingLifetime = Duration(days: 1);

  /// Who invited us to each room, seen while the invite was active.
  final Map<String, String> _inviters = {};
  final Map<String, List<_PendingBundle>> _pending = {};
  final Map<String, RoomKeyBundleImport> _lastImports = {};

  final StreamController<RoomKeyBundleImport> onImported =
      StreamController.broadcast();
  final StreamController<RoomKeyBundleRejection> onRejected =
      StreamController.broadcast();

  RoomKeyBundleManager(this.encryption);

  /// The last bundle imported for [roomId] since the app started.
  RoomKeyBundleImport? lastImport(String roomId) => _lastImports[roomId];

  /// Shares [room]'s history with [userId], just invited. Returns how many
  /// sessions went out; 0 when nothing was uploaded nor sent.
  Future<int> shareHistoryWith(Room room, String userId) async {
    if (!room.encrypted || !client.encryptionEnabled) return 0;
    // The history visibility and the invitee's membership are not kept in
    // memory until the room's state is loaded.
    await room.postLoad();
    if (!roomSharesHistoryOnInvite(room.historyVisibility)) {
      Logs().i('[RoomKeyBundle] History visibility keeps keys to members');
      return 0;
    }
    if (userId == client.userID) return 0;
    final membership = room
        .getState(EventTypes.RoomMember, userId)
        ?.content
        .tryGet<String>('membership');
    if (membership == Membership.ban.name) return 0;

    // The invitee may share no encrypted room with us yet.
    if (client.userDeviceKeys[userId]?.outdated != false) {
      await client.updateUserDeviceKeys(
        additionalUsers: {userId},
        onlyAdditionalUsers: true,
      );
    }
    // The devices room keys go to (`Client.shareKeysWith`, never blocked),
    // as `KeyManager` picks them for a new Megolm session.
    final devices = (client.userDeviceKeys[userId]?.deviceKeys.values ??
            const <DeviceKeys>[])
        .where((d) => d.encryptToDevice && d.isValid)
        .toList();
    if (devices.isEmpty) {
      Logs().i('[RoomKeyBundle] The invitee has no device to share with');
      return 0;
    }

    final roomKeys = await _shareableSessions(room.id);
    if (roomKeys.isEmpty) return 0;

    final plain = utf8.encode(
      json.encode({'room_keys': roomKeys, 'withheld': <Object>[]}),
    );
    final encrypted = await encryptFile(plain);
    final uri = await client.uploadContent(
      encrypted.data,
      filename: 'room_key_bundle',
      contentType: 'application/octet-stream',
    );
    final content = RoomKeyBundleContent(
      roomId: room.id,
      file: {
        'url': uri.toString(),
        'key': {
          'kty': 'oct',
          'key_ops': ['encrypt', 'decrypt'],
          'alg': 'A256CTR',
          'k': encrypted.k,
          'ext': true,
        },
        'iv': encrypted.iv,
        'hashes': {'sha256': encrypted.sha256},
        'v': 'v2',
      },
    );
    await client.sendToDeviceEncrypted(
      devices,
      EventTypes.RoomKeyBundle,
      content.toJson(),
    );
    return roomKeys.length;
  }

  Future<List<Map<String, Object?>>> _shareableSessions(String roomId) async {
    final userId = client.userID!;
    final keys = <Map<String, Object?>>[];
    for (final stored in await client.database.getAllInboundGroupSessions()) {
      if (stored.roomId != roomId) continue;
      final session = SessionKey.fromDb(stored, userId);
      final inbound = session.inboundGroupSession;
      if (!session.isValid || inbound == null) continue;
      if (session.content[sharedHistoryKey] != true) continue;
      final claimed = session.senderClaimedKeys['ed25519'] ??
          (session.senderKey == encryption.identityKey
              ? encryption.fingerprintKey
              : null);
      keys.add({
        'algorithm': AlgorithmTypes.megolmV1AesSha2,
        'room_id': roomId,
        'sender_key': session.senderKey,
        'session_id': session.sessionId,
        'session_key': inbound.exportAtFirstKnownIndex(),
        'sender_claimed_keys': {if (claimed != null) 'ed25519': claimed},
        'forwarding_curve25519_key_chain': session.forwardingCurve25519KeyChain,
        sharedHistoryKey: true,
      });
    }
    return keys;
  }

  void _reject(RoomKeyBundleRejection why) {
    Logs().w('[RoomKeyBundle] Bundle refused: ${why.name}');
    onRejected.add(why);
  }

  /// An `m.room_key_bundle` came in: checked now, taken in once we join.
  Future<void> handleToDeviceEvent(ToDeviceEvent event) async {
    final senderKey = event.encryptedContent?['sender_key'];
    if (senderKey is! String) {
      return _reject(RoomKeyBundleRejection.notEncrypted);
    }
    final content = RoomKeyBundleContent.tryFromJson(event.content);
    if (content == null) return _reject(RoomKeyBundleRejection.malformed);
    if (!_trustedSender(event.sender, senderKey)) {
      return _reject(RoomKeyBundleRejection.untrustedDevice);
    }
    // Kept until the sync is through (the invite may come in it, after the
    // to-device events) and taken in once we join: `processPending`.
    final room = client.getRoomById(content.roomId);
    if (room != null) {
      _noteInviter(room);
      final inviter = _inviters[room.id];
      if (inviter != null && inviter != event.sender) {
        return _reject(RoomKeyBundleRejection.notInvitedBySender);
      }
    }
    (_pending[content.roomId] ??= []).add(
      _PendingBundle(event.sender, senderKey, content, DateTime.now()),
    );
  }

  /// The device that sent the bundle, by the Olm session's Curve25519 key,
  /// must be known, not blocked and, if its owner cross-signs, signed.
  bool _trustedSender(String userId, String senderKey) {
    final keys = client.userDeviceKeys[userId];
    final device = keys?.deviceKeys.values
        .firstWhereOrNull((d) => d.curve25519Key == senderKey);
    if (device == null || device.blocked || !device.isValid) return false;
    if (keys!.masterKey == null) return true;
    return device.hasValidSignatureChain(verifiedByTheirMasterKey: true);
  }

  void _noteInviter(Room room) {
    if (room.membership != Membership.invite) return;
    final member = room.getState(EventTypes.RoomMember, client.userID!);
    if (member?.content.tryGet<String>('membership') != 'invite') return;
    _inviters[room.id] = member!.senderId;
  }

  /// Called after each sync: notes who invited us, drops bundles of rooms we
  /// left or that waited too long, and takes in those of rooms we joined.
  Future<void> processPending() async {
    for (final room in client.rooms) {
      if (room.membership == Membership.invite) _noteInviter(room);
    }
    final now = DateTime.now();
    for (final roomId in _pending.keys.toList()) {
      final bundles = _pending[roomId];
      if (bundles == null) continue;
      bundles.removeWhere((b) => now.difference(b.received) > pendingLifetime);
      final room = client.getRoomById(roomId);
      if (room != null &&
          (room.membership == Membership.leave ||
              room.membership == Membership.ban)) {
        // The invite was turned down or taken back.
        _pending.remove(roomId);
        _inviters.remove(roomId);
        for (var i = 0; i < bundles.length; i++) {
          _reject(RoomKeyBundleRejection.inviteNotActive);
        }
        continue;
      }
      if (bundles.isEmpty) {
        _pending.remove(roomId);
        continue;
      }
      if (room == null || room.membership != Membership.join) continue;
      _pending.remove(roomId);
      final inviter = _inviters[roomId];
      for (final bundle in bundles) {
        if (inviter == null || bundle.senderId != inviter) {
          _reject(RoomKeyBundleRejection.notInvitedBySender);
          continue;
        }
        await _import(room, bundle);
      }
    }
  }

  Future<void> _import(Room room, _PendingBundle bundle) async {
    final file = bundle.content.file;
    final url = file.tryGet<String>('url');
    final key = file.tryGetMap<String, Object?>('key');
    final k = key?.tryGet<String>('k');
    final iv = file.tryGet<String>('iv');
    final sha256 =
        file.tryGetMap<String, Object?>('hashes')?.tryGet<String>('sha256');
    final mxc = url == null ? null : Uri.tryParse(url);
    if (mxc == null ||
        !mxc.isScheme('mxc') ||
        k == null ||
        iv == null ||
        sha256 == null ||
        key?.tryGetList<String>('key_ops')?.contains('decrypt') != true) {
      return _reject(RoomKeyBundleRejection.malformed);
    }

    final Uint8List data;
    try {
      final downloaded = await _download(mxc);
      if (downloaded == null) {
        return _reject(RoomKeyBundleRejection.tooLarge);
      }
      data = downloaded;
    } catch (e) {
      Logs().w('[RoomKeyBundle] Download failed', e);
      return _reject(RoomKeyBundleRejection.downloadFailed);
    }
    final plain = await client.nativeImplementations.decryptFile(
      EncryptedFile(data: data, k: k, iv: iv, sha256: sha256),
    );
    if (plain == null) return _reject(RoomKeyBundleRejection.hashMismatch);

    final sessions = <(Map<String, Object?>, vod.InboundGroupSession)>[];
    try {
      final decoded = json.decode(utf8.decode(plain));
      final roomKeys = (decoded as Map)['room_keys'] as List;
      for (final raw in roomKeys) {
        final entry = (raw as Map).cast<String, Object?>();
        if (entry['room_id'] != room.id) {
          return _reject(RoomKeyBundleRejection.wrongRoom);
        }
        final sessionKey = entry['session_key'];
        if (entry['algorithm'] != AlgorithmTypes.megolmV1AesSha2 ||
            entry['sender_key'] is! String ||
            entry['session_id'] is! String ||
            sessionKey is! String) {
          return _reject(RoomKeyBundleRejection.malformed);
        }
        final session = vod.InboundGroupSession.import(sessionKey);
        if (session.sessionId != entry['session_id']) {
          return _reject(RoomKeyBundleRejection.malformed);
        }
        sessions.add((entry, session));
      }
    } catch (_) {
      return _reject(RoomKeyBundleRejection.malformed);
    }

    final keyManager = encryption.keyManager;
    var imported = 0;
    for (final (entry, session) in sessions) {
      final sessionId = entry['session_id'] as String;
      final senderKey = entry['sender_key'] as String;
      final existing =
          await keyManager.loadInboundGroupSession(room.id, sessionId);
      // Never over a session received from its sender (`m.room_key`), nor
      // one that starts as early or earlier.
      if (existing != null &&
          (existing.forwardingCurve25519KeyChain.isEmpty ||
              (existing.inboundGroupSession?.firstKnownIndex ?? 0) <=
                  session.firstKnownIndex)) {
        continue;
      }
      // The claimed key, as for `m.room_key` (T3.1b): the one of the known
      // device whose Curve25519 key is the session's, never what the
      // bundle writes.
      final claimed = senderKey == encryption.identityKey
          ? encryption.fingerprintKey
          : client.getUserDeviceKeysByCurve25519Key(senderKey)?.ed25519Key;
      final chain = entry.tryGetList<String>('forwarding_curve25519_key_chain');
      await keyManager.setInboundGroupSession(
        room.id,
        sessionId,
        senderKey,
        {
          'algorithm': AlgorithmTypes.megolmV1AesSha2,
          'room_id': room.id,
          'session_id': sessionId,
          'session_key': entry['session_key'],
          'forwarding_curve25519_key_chain': [
            ...?chain,
            bundle.senderKey,
          ],
          sharedHistoryKey: true,
        },
        forwarded: true,
        senderClaimedKeys: {if (claimed != null) 'ed25519': claimed},
        claimDeviceOfSenderKey: false,
      );
      imported++;
    }
    final result = RoomKeyBundleImport(
      roomId: room.id,
      senderId: bundle.senderId,
      imported: imported,
      skipped: sessions.length - imported,
      when: DateTime.now(),
    );
    _lastImports[room.id] = result;
    onImported.add(result);
  }

  /// Downloads [mxc] through the authenticated media API when the server
  /// has it; null when it is larger than [maxBundleBytes], which is checked
  /// on the declared length and while reading, before any decryption.
  Future<Uint8List?> _download(Uri mxc) async {
    final request = http.Request('GET', await mxc.getDownloadUri(client));
    request.headers['authorization'] = 'Bearer ${client.accessToken}';
    final response = await client.httpClient.send(request);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final declared = response.contentLength;
    if (declared != null && declared > maxBundleBytes) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (builder.length + chunk.length > maxBundleBytes) return null;
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void dispose() {
    unawaited(onImported.close());
    unawaited(onRejected.close());
  }
}
