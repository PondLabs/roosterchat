// ROOSTER: What lets the sync loop change between Simplified Sliding Sync
// (MSC4186) and `/v3/sync` without losing or repeating a to-device
// message or a device list change. The two have independent positions
// (`pos` and the to-device `since` against `since`/`next_batch`), so what
// one delivered and the server has not been told yet, the other delivers
// again. See third_party/README.md, "Simplified Sliding Sync".

import 'dart:convert';

import 'package:canonical_json/canonical_json.dart';

import 'package:matrix/matrix.dart';

/// Stored in the custom cache, written with the sync it describes.
class SyncTransportContinuity {
  static const cacheKey = 'rooster_sliding_sync';

  /// The transport of the last processed sync.
  SyncTransport? transport;

  /// The `/v3/sync` token when Sliding Sync took over: where `/v3/sync`
  /// goes on from if it has to come back.
  String? legacySince;

  /// The Sliding Sync connection, to go on after a restart.
  String? pos;
  String? toDeviceSince;

  /// The to-device messages of the last processed sync. The server deletes
  /// them only when the next request of the same transport acknowledges
  /// them, so the other transport gets them again.
  Set<String> toDevice;

  /// The users Sliding Sync reported in `device_lists` since it took over:
  /// a `/v3/sync` from [legacySince] reports them again.
  Set<String> changed;
  Set<String> left;

  SyncTransportContinuity({
    this.transport,
    this.legacySince,
    this.pos,
    this.toDeviceSince,
    Set<String>? toDevice,
    Set<String>? changed,
    Set<String>? left,
  })  : toDevice = toDevice ?? {},
        changed = changed ?? {},
        left = left ?? {};

  factory SyncTransportContinuity.fromJson(Map<String, Object?> json) =>
      SyncTransportContinuity(
        transport: SyncTransport.values
            .where((t) => t.name == json['transport'])
            .firstOrNull,
        legacySince: json.tryGet<String>('legacy_since'),
        pos: json.tryGet<String>('pos'),
        toDeviceSince: json.tryGet<String>('to_device_since'),
        toDevice: json.tryGetList<String>('to_device')?.toSet(),
        changed: json.tryGetList<String>('changed')?.toSet(),
        left: json.tryGetList<String>('left')?.toSet(),
      );

  Map<String, Object?> toJson() => {
        if (transport != null) 'transport': transport!.name,
        if (legacySince != null) 'legacy_since': legacySince,
        if (pos != null) 'pos': pos,
        if (toDeviceSince != null) 'to_device_since': toDeviceSince,
        'to_device': toDevice.toList(),
        'changed': changed.toList(),
        'left': left.toList(),
      };

  /// A short, stable name of a to-device message: who sent it, its type
  /// and its content. An encrypted message's ciphertext is unique, and
  /// the others carry a request or transaction id.
  static String fingerprint(BasicEventWithSender event) {
    final text = utf8.decode(
      canonicalJson.encode({
        'sender': event.senderId,
        'type': event.type,
        'content': event.content,
      }),
    );
    // Two 30-bit hashes: exact on the web, where ints are doubles.
    var a = 17, b = 23;
    for (final unit in text.codeUnits) {
      a = (a * 31 + unit) & 0x3fffffff;
      b = (b * 131 + unit) & 0x3fffffff;
    }
    return '${text.length.toRadixString(36)}.${a.toRadixString(36)}'
        '.${b.toRadixString(36)}';
  }

  /// Removes from [update] what the other transport delivered already, when
  /// [update] is the first of [now] after it. Returns the users whose
  /// `device_lists.changed` entry was a repeat, but whose keys were
  /// downloaded since: a `/v3/sync` token from before cannot tell a repeat
  /// from a newer change, so the client checks their keys once.
  Set<String> dropRepeats(SyncUpdate update, SyncTransport now) {
    if (transport == null || transport == now) return const {};
    final toDeviceEvents = update.toDevice;
    if (toDeviceEvents != null && toDevice.isNotEmpty) {
      update.toDevice = toDeviceEvents
          .where((event) => !toDevice.contains(fingerprint(event)))
          .toList();
    }
    final lists = update.deviceLists;
    if (now != SyncTransport.v3 || lists == null) return const {};
    final repeated = {...?lists.changed}.intersection(changed);
    lists.changed = lists.changed?.where((u) => !changed.contains(u)).toList();
    lists.left = lists.left?.where((u) => !left.contains(u)).toList();
    return repeated;
  }

  /// Records [update], processed through [now]: [delivered] is its
  /// to-device messages as they came, before [dropRepeats].
  void record(
    SyncUpdate update,
    SyncTransport now, {
    required List<BasicEventWithSender> delivered,
  }) {
    toDevice = delivered.map(fingerprint).toSet();
    if (now == SyncTransport.v3) {
      changed.clear();
      left.clear();
    } else {
      if (transport != now) {
        changed.clear();
        left.clear();
      }
      changed.addAll(update.deviceLists?.changed ?? []);
      left.addAll(update.deviceLists?.left ?? []);
    }
    transport = now;
  }
}
