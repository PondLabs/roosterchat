import 'dart:convert';
import 'dart:typed_data';

import 'package:matrix/encryption/utils/session_key.dart';
import 'package:matrix/matrix.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import 'megolm_export_format.dart';

/// How an import went: of the file's [total] sessions, [imported] were
/// kept and [alreadyHeld] were not, because this device holds them from
/// the same message or an earlier one; the others were not room key
/// sessions this app can use.
class KeyImportResult {
  const KeyImportResult({
    required this.total,
    required this.imported,
    this.alreadyHeld = 0,
  });

  final int total;
  final int imported;
  final int alreadyHeld;

  /// The file's entries that were not usable room key sessions.
  int get unusable => total - imported - alreadyHeld;
}

/// What the key export panel asks of the account, so a test can stand in
/// for it.
abstract class KeyPortabilityController {
  /// Every room key session this device holds, as a key export file
  /// encrypted with [passphrase]; and how many sessions it holds.
  Future<({Uint8List file, int count})> exportKeys(String passphrase);

  /// Reads the key export [file] with [passphrase] and keeps its sessions.
  /// Throws a [MegolmExportException] when the file is not a key export,
  /// is damaged or the passphrase is wrong, before anything is kept.
  Future<KeyImportResult> importKeys(Uint8List file, String passphrase);
}

/// Room key export and import for a Matrix account: the sessions of its
/// database, in the spec's key export format ([MegolmExportFormat]).
class MegolmKeyPortability implements KeyPortabilityController {
  MegolmKeyPortability(this.client,
      {this.rounds = MegolmExportFormat.defaultRounds});

  final Client client;

  /// PBKDF2 rounds of the files this account writes.
  final int rounds;

  /// The sessions of [client]'s database, each as the spec's
  /// `ExportedSessionData`: the session from its first known index, which
  /// is what the online key backup keeps of it too.
  Future<List<Map<String, Object?>>> exportedSessions() async {
    final userId = client.userID;
    if (userId == null || client.encryption == null) {
      throw StateError('Encryption is not enabled for this account');
    }
    final sessions = <Map<String, Object?>>[];
    for (final stored in await client.database.getAllInboundGroupSessions()) {
      final SessionKey session;
      try {
        session = SessionKey.fromDb(stored, userId);
      } catch (_) {
        continue; // A session this device cannot read: nothing to export.
      }
      final inbound = session.inboundGroupSession;
      if (inbound == null) continue;
      sessions.add({
        'algorithm': AlgorithmTypes.megolmV1AesSha2,
        'forwarding_curve25519_key_chain': session.forwardingCurve25519KeyChain,
        'room_id': session.roomId,
        'sender_key': session.senderKey,
        'sender_claimed_keys': session.senderClaimedKeys,
        'session_id': session.sessionId,
        'session_key': inbound.exportAtFirstKnownIndex(),
      });
    }
    return sessions;
  }

  @override
  Future<({Uint8List file, int count})> exportKeys(String passphrase) async {
    final sessions = await exportedSessions();
    final text =
        await MegolmExportFormat.encrypt(sessions, passphrase, rounds: rounds);
    return (
      file: Uint8List.fromList(utf8.encode(text)),
      count: sessions.length
    );
  }

  @override
  Future<KeyImportResult> importKeys(Uint8List file, String passphrase) async {
    final keyManager = client.encryption?.keyManager;
    if (keyManager == null) {
      throw StateError('Encryption is not enabled for this account');
    }
    // Decrypted and checked whole before anything is kept: a wrong
    // passphrase or a damaged file leaves the database as it was.
    final sessions = await MegolmExportFormat.decrypt(file, passphrase);
    final usable = sessions.where(_usable).toList();
    var imported = 0;
    for (final session in usable) {
      final roomId = session['room_id'] as String;
      final sessionId = session['session_id'] as String;
      final senderClaimedKeys =
          session.tryGetMap<String, Object?>('sender_claimed_keys') ?? const {};
      // The session this device holds, out of its database: the SDK keeps
      // the better of the two, but compares only with what is in memory,
      // and after a restart nothing is until a message needs it. Without
      // this, a file's later copy would replace an earlier one, and the
      // messages before it would no longer decrypt.
      final held = await keyManager.loadInboundGroupSession(roomId, sessionId);
      await keyManager.setInboundGroupSession(
        roomId,
        sessionId,
        session['sender_key'] as String,
        {
          'algorithm': AlgorithmTypes.megolmV1AesSha2,
          'room_id': session['room_id'],
          'session_id': session['session_id'],
          'session_key': session['session_key'],
          'forwarding_curve25519_key_chain':
              session.tryGetList<String>('forwarding_curve25519_key_chain') ??
                  const <String>[],
        },
        // An exported session is one from its first known index, as a
        // forwarded key is (not the `m.room_key` a sender shares).
        forwarded: true,
        senderClaimedKeys: {
          for (final entry in senderClaimedKeys.entries)
            if (entry.value is String) entry.key: entry.value as String,
        },
      );
      // Kept only when it took the place of [held] (or of nothing).
      final now = keyManager.getInboundGroupSession(roomId, sessionId);
      if (now != null && !identical(now, held)) imported++;
    }
    return KeyImportResult(
      total: sessions.length,
      imported: imported,
      alreadyHeld: usable.length - imported,
    );
  }

  /// A Megolm session whose ids and key are there, and whose key vodozemac
  /// reads, with the session id it says it has.
  static bool _usable(Map<String, Object?> session) {
    if (session['algorithm'] != AlgorithmTypes.megolmV1AesSha2) return false;
    final roomId = session['room_id'];
    final sessionId = session['session_id'];
    final senderKey = session['sender_key'];
    final sessionKey = session['session_key'];
    if (roomId is! String ||
        sessionId is! String ||
        senderKey is! String ||
        sessionKey is! String) {
      return false;
    }
    try {
      return vod.InboundGroupSession.import(sessionKey).sessionId == sessionId;
    } catch (_) {
      return false;
    }
  }
}
