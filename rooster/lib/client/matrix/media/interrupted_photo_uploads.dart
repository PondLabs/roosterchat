/// The photos sent before their upload (`async_photo_send.dart`) whose
/// event left and whose upload had not ended, kept in the account's
/// database with no content: the room, the event's id and its transaction
/// id, as local account data the homeserver never gets. A photo leaves the
/// list when its upload ends: up, or failed or cancelled and taken back.
///
/// One still on the list when the account opens again was cut short by
/// the app closing: its message is in the room pointing at media that
/// never came. It is settled as an upload that failed for good: the
/// message is taken back (redacted), its files leave the own media, and a
/// failed message of this device says the photo did not upload. That one
/// has no "Retry": the photo's bytes went with the app. A redaction that
/// fails leaves it on the list, to be tried again at the next opening, and
/// the sent message says it is still in the room.
library;

import 'dart:async';

import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/media/async_photo_send.dart';
import 'package:rooster/client/matrix/media/own_media.dart';
import 'package:rooster/debug/log.dart';

/// The local account data the list is kept under.
const photoUploadsAfterEventType = 'chat.rooster.photo_uploads_after_event';

/// In a failed message left by [settleInterruptedPhotoUploads], the id of
/// the photo message that did not upload.
const interruptedPhotoKey = 'chat.rooster.interrupted_photo';

/// Whether [event] is a failed message left for a photo whose upload the
/// app's closing cut short: it says so, and has no "Retry".
bool isInterruptedPhotoMessage(matrix.Event event) =>
    event.content[interruptedPhotoKey] is String;

class _Ledger {
  _Ledger(this.entries)
      : fromBefore = {for (final e in entries) e['txid'] as String?};

  final List<Map<String, Object?>> entries;

  /// The transaction ids on the list when it was read from the database:
  /// sends of an earlier opening, none of them still running.
  final Set<String?> fromBefore;

  Future<void> writing = Future.value();
}

final _ledgers = Expando<_Ledger>('photo uploads after event');

_Ledger _ledgerOf(matrix.Client client) {
  final existing = _ledgers[client];
  if (existing != null) return existing;
  final stored = client.accountData[photoUploadsAfterEventType]?.content;
  final uploads = stored?['uploads'];
  return _ledgers[client] = _Ledger([
    if (uploads is List)
      for (final entry in uploads)
        if (entry is Map) Map<String, Object?>.from(entry),
  ]);
}

/// Writes the list, after any write before it. Never throws.
Future<void> _save(matrix.Client client, _Ledger ledger) {
  final content = {
    'uploads': [for (final entry in ledger.entries) Map.of(entry)],
  };
  return ledger.writing = ledger.writing
      .then((_) =>
          client.database.storeAccountData(photoUploadsAfterEventType, content))
      .catchError((Object error, StackTrace stack) {
    Log.onError(error, stack, content: "Could not keep the photos uploading");
  });
}

/// The photo [txid] of [room], whose event [eventId] was sent, starts its
/// upload: on the list until [photoUploadEnded]. Ends once it is written.
Future<void> photoUploadStarted(matrix.Room room, String txid, String eventId) {
  final ledger = _ledgerOf(room.client);
  ledger.entries.add({'room': room.id, 'event': eventId, 'txid': txid});
  return _save(room.client, ledger);
}

/// The upload of the photo [txid] ended: off the list. When its message
/// could not be taken back, it stays, with [failedMessageId] (the failed
/// message already shown), so the next opening tries the redaction again.
Future<void> photoUploadEnded(matrix.Client client, String txid,
    {String? failedMessageId}) {
  final ledger = _ledgerOf(client);
  if (failedMessageId != null) {
    for (final entry in ledger.entries) {
      if (entry['txid'] == txid) entry['item'] = failedMessageId;
    }
  } else {
    ledger.entries.removeWhere((entry) => entry['txid'] == txid);
  }
  return _save(client, ledger);
}

/// Settles the photos of an earlier opening whose upload never ended (see
/// the library doc). Never throws.
Future<void> settleInterruptedPhotoUploads(matrix.Client client) async {
  final ledger = _ledgerOf(client);
  for (final entry in List.of(ledger.entries)) {
    if (!ledger.fromBefore.contains(entry['txid'])) continue;
    try {
      await _settle(client, ledger, entry);
    } catch (error, stack) {
      Log.onError(error, stack, content: "Could not settle a photo upload");
    }
  }
}

Future<void> _settle(
    matrix.Client client, _Ledger ledger, Map<String, Object?> entry) async {
  final room = client.getRoomById(entry['room'] as String? ?? '');
  final eventId = entry['event'] as String?;
  final txid = entry['txid'] as String?;
  if (room == null || eventId == null || txid == null) {
    ledger.entries.remove(entry);
    await _save(client, ledger);
    return;
  }

  // Whatever of it the own media holds (opened full size during the
  // upload, say) is a picture the others never get.
  final event = await client.database.getEventById(eventId, room);
  if (event != null) {
    final keys = <String>[];
    for (final thumbnail in [false, true]) {
      try {
        final mxc = event.attachmentOrThumbnailMxcUrl(getThumbnail: thumbnail);
        if (mxc != null) keys.add(mxc.toString());
      } catch (_) {}
    }
    await forgetOwnMedia(client, keys);
  }

  if (entry['item'] == null) {
    final item = client.generateUniqueTransactionId();
    entry['item'] = item;
    await _save(client, ledger);
    await room.showFailedMessage(item, {
      'msgtype': matrix.MessageTypes.Notice,
      // Not translated: the timeline shows labelPhotoUploadInterrupted in
      // its place; this body is never sent.
      'body': "A photo didn't finish uploading before Rooster closed",
      interruptedPhotoKey: eventId,
    });
  }

  try {
    await room.redactEvent(eventId);
  } catch (error, stack) {
    Log.onError(error, stack,
        content: "Could not take back a photo the app's closing cut short");
    markPhotoLeftInRoom(client, [txid, eventId]);
    return;
  }
  ledger.entries.remove(entry);
  await _save(client, ledger);
}
