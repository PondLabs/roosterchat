// The wire format of call activities on the call's LiveKit data channel.
// Mirrors the DJ booth's protocol (../dj/dj_protocol.dart): JSON objects
// with a `t` type, one reliable topic, large messages sent as numbered
// parts put back together by the receiver. The game's own payloads ride
// their own topic (chat.commet.putt.v1 and friends); everything here is
// session control only.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// The session-control topic.
const callActivityTopic = 'chat.commet.activity.v1';

/// Message types, the values of `t`.
abstract final class CallActivityMessageType {
  /// Someone arrived in the call, or came back from a reconnect, and wants
  /// the current session. Answered with [state], or nothing when there is
  /// none.
  static const hello = 'hello';

  /// What the sender's client can do: which activities it knows (`acts`),
  /// whether it can host one (`host`), its platform (`p`). Sent on joining
  /// and on request.
  static const caps = 'caps';

  /// A session descriptor from the host: which activity, the session and
  /// host ids, the epoch and the state version. Sent when a session
  /// launches and on a sync's behalf.
  static const announce = 'announce';

  /// Ask to join a session, as a player or a spectator.
  static const join = 'join';

  /// The host's answer to a join that it accepted, sent back to the joiner.
  static const joined = 'joined';

  /// The host grants one participant the right to send game input.
  static const inputLease = 'input-lease';

  /// The full state of the session: framework metadata plus the activity's
  /// own snapshot, with the sequence number counting snapshots.
  static const state = 'state';

  /// A participant announces it left the session.
  static const leave = 'leave';

  /// The session is over: the host is ending it.
  static const bye = 'bye';

  /// A new host takes over after the old one vanished without handing off.
  static const hostElected = 'host-elected';

  /// A host leaving on purpose offers the seat to another player.
  static const handoffOffer = 'handoff-offer';

  /// The offered player takes the seat.
  static const handoffAck = 'handoff-ack';

  /// A handoff target failed to take over: the host carries on.
  static const pfail = 'pfail';

  /// One piece of a message too large for one packet.
  static const part = 'part';

  /// A player's move in the activity's own language: a shot, a power-up
  /// order. Only the host acts on it; the answer rides the next state.
  static const input = 'input';

  /// The host's fast lane: an opaque message to everyone (the activity's
  /// own relayings, like the accepted-move journal it streams between
  /// snapshots). Only the host's messages count.
  static const relay = 'relay';

  /// An opaque message from any participant to the participants it chose
  /// (the transport addresses it; the body does not say to whom). What an
  /// activity with secrets sends: nobody else in the call receives it.
  static const direct = 'direct';
}

/// The wire format itself. The packet limit, the part sizes and the
/// assembler's behaviour are the DJ booth's, unchanged: same transport, same
/// limits, one shape to learn.
abstract final class CallActivityProtocol {
  /// The topic every message rides.
  static const topic = callActivityTopic;

  /// Largest message sent whole, in bytes.
  static const maxPacketBytes = 14000;

  /// Characters of JSON per part; at 3 UTF-8 bytes per character plus the
  /// part's own wrapping, comfortably under [maxPacketBytes].
  static const partChars = 3500;

  /// Most parts in one message: about 450 KB of JSON, a full state
  /// snapshot with room to spare.
  static const maxParts = 128;

  /// How long an incomplete (partly received) message is kept before its
  /// parts are dropped: the sender is expected to have given up or to
  /// retry the whole message.
  static const partTimeout = Duration(seconds: 30);

  /// Most incomplete messages kept per sender; the oldest go first.
  static const maxPendingPerSender = 3;

  static final Random _random = Random();

  /// The messages to send for [message]: [message] itself when it fits in a
  /// packet, otherwise its parts, numbered `0..n-1`, to be put back
  /// together by [CallPartAssembler]. Null when even the parts would not
  /// fit the parts limit.
  static List<Map<String, Object?>>? split(Map<String, Object?> message) {
    final text = jsonEncode(message);
    if (utf8.encode(text).length <= maxPacketBytes) return [message];

    final count = (text.length / partChars).ceil();
    if (count > maxParts) return null;

    final id = _random.nextInt(1 << 31).toRadixString(36);
    return [
      for (var i = 0; i < count; i++)
        {
          't': CallActivityMessageType.part,
          'id': id,
          'i': i,
          'n': count,
          'd': text.substring(
              i * partChars, min(text.length, (i + 1) * partChars)),
        }
    ];
  }

  /// Encodes one message to one packet's bytes.
  static Uint8List encodePacket(Map<String, Object?> message) =>
      utf8.encode(jsonEncode(message));

  /// Parses one packet. Null when it is not JSON or not an envelope: a
  /// message with no `t`.
  static Map<String, Object?>? decodePacket(Uint8List data) {
    if (data.length > maxPacketBytes * 2) return null;
    try {
      final json = jsonDecode(utf8.decode(data));
      if (json is Map<String, Object?> && json['t'] is String) return json;
    } catch (_) {}
    return null;
  }
}

/// Puts [CallActivityProtocol.split]'s parts back together, per sender.
/// Envelopes that arrive whole are returned as they came; a message is
/// handed up once all its parts are in.
class CallPartAssembler {
  final Map<String, _PendingPart> _pending = {};

  /// Returns the message [sender] has sent, in [packet]: the message
  /// itself, the message [part] completes, or null (keep waiting, or a
  /// part that belongs to nothing sensible).
  Map<String, Object?>? add(String sender, Map<String, Object?> packet,
      {DateTime? now}) {
    now ??= DateTime.now();

    if (packet['t'] != CallActivityMessageType.part) return packet;
    final id = packet['id'];
    final index = packet['i'];
    final count = packet['n'];
    final data = packet['d'];
    if (id is! String || id.isEmpty || id.length > 20) return null;
    if (index is! int || count is! int || count < 1) return null;
    if (count > CallActivityProtocol.maxParts ||
        index < 0 ||
        index >= count ||
        data is! String) {
      return null;
    }

    final key = '$sender\\n$id';
    var pending = _pending[key];
    if (pending != null &&
        pending.started
            .isBefore(now.subtract(CallActivityProtocol.partTimeout))) {
      _pending.remove(key);
      pending = null;
    }
    if (pending == null) {
      // Incomplete messages a sender has stopped filling (gave up, or the
      // receiver asked again) go, oldest first, so a receiver holds at
      // most a few per sender.
      final mine = _pending.keys.where((k) => k.startsWith('$sender\\n'));
      for (final key in mine.take(max(
          0, _pending.length + 1 - CallActivityProtocol.maxPendingPerSender))) {
        _pending.remove(key);
      }
      pending = _pending[key] = _PendingPart(count, now);
    }
    if (pending.parts.length != count) return null;
    if (pending.parts[index] != null) return null;
    pending.parts[index] = data;
    if (pending.parts.any((p) => p == null)) return null;

    _pending.remove(key);
    try {
      final json = jsonDecode(pending.parts.join());
      if (json is Map<String, Object?> && json['t'] is String) return json;
    } catch (_) {}
    return null;
  }
}

class _PendingPart {
  final DateTime started;
  final parts = <String?>[];

  _PendingPart(int count, this.started) {
    parts.length = count;
  }
}
