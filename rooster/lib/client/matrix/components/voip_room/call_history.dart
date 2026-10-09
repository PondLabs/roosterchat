// What happened in a voice channel, worked out from its call memberships'
// history: who was in which call, for how long, and what they shared. Every
// write of a membership stays in the room's history (a join, each rewrite
// with what its owner advertises, and an empty one on leaving), so the room
// itself is the record. See docs/call-history.md.
import 'package:rooster/client/components/activities/activities_component.dart';
import 'package:rooster/client/matrix/components/voip_room/matrix_call_membership.dart';

/// One write of a call membership, as the room's history has it.
class CallMemberRecord {
  const CallMemberRecord({
    required this.sender,
    required this.stateKey,
    required this.sentAt,
    required this.content,
  });

  final String sender;

  /// One per device: a membership's writes share it.
  final String stateKey;

  /// When the homeserver took it (`origin_server_ts`).
  final DateTime sentAt;
  final Map<String, Object?> content;
}

/// Something a member did in a call besides being there.
enum CallActivity { screen, camera, dj }

/// A stretch of time.
class TimeSpan {
  const TimeSpan(this.start, this.end);
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  /// The part of it inside [other], or null when they do not overlap.
  TimeSpan? clip(TimeSpan other) {
    final s = start.isAfter(other.start) ? start : other.start;
    final e = end.isBefore(other.end) ? end : other.end;
    return e.isAfter(s) ? TimeSpan(s, e) : null;
  }

  @override
  String toString() => "TimeSpan($start, $end)";
}

/// One call: a stretch of time with someone in the channel.
class VoiceCall {
  VoiceCall({
    required this.roomId,
    required this.span,
    required this.ongoing,
    required this.presence,
    required this.activities,
    required this.peak,
  });

  final String roomId;
  final TimeSpan span;

  /// Someone is still in it.
  final bool ongoing;

  /// When each member was in it, their devices together.
  final Map<String, List<TimeSpan>> presence;

  /// When each member shared their screen, their camera, or played music.
  final Map<String, Map<CallActivity, List<TimeSpan>>> activities;

  /// The most people in it at once.
  final int peak;

  Duration timeOf(String userId, [TimeSpan? within]) =>
      _total(presence[userId] ?? const [], within);

  Duration activityOf(String userId, CallActivity activity,
          [TimeSpan? within]) =>
      _total(activities[userId]?[activity] ?? const [], within);

  /// Everyone who was in it, longest first.
  List<String> get members {
    final users = presence.keys.toList();
    users.sort((a, b) => timeOf(b).compareTo(timeOf(a)));
    return users;
  }
}

Duration _total(Iterable<TimeSpan> spans, TimeSpan? within) {
  var total = Duration.zero;
  for (final span in spans) {
    final part = within == null ? span : span.clip(within);
    if (part != null) total += part.duration;
  }
  return total;
}

/// What a day (or any [window]) looked like across [calls].
class VoiceActivitySummary {
  VoiceActivitySummary(this.window, Iterable<VoiceCall> calls)
      : calls = calls.where((c) => c.span.clip(window) != null).toList()
          ..sort((a, b) => a.span.start.compareTo(b.span.start));

  final TimeSpan window;

  /// The calls with any part in [window], earliest first.
  final List<VoiceCall> calls;

  /// Time with anyone in voice, inside [window].
  Duration get callTime => _total(calls.map((c) => c.span), window);

  /// Each member's time in voice inside [window], most first.
  List<MapEntry<String, Duration>> get timeByMember {
    final totals = <String, Duration>{};
    for (final call in calls) {
      for (final user in call.presence.keys) {
        totals[user] =
            (totals[user] ?? Duration.zero) + call.timeOf(user, window);
      }
    }
    final entries = totals.entries.where((e) => e.value > Duration.zero);
    return entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Each member's time doing [activity] inside [window].
  Map<String, Duration> activityByMember(CallActivity activity) {
    final totals = <String, Duration>{};
    for (final call in calls) {
      for (final user in call.activities.keys) {
        final time = call.activityOf(user, activity, window);
        if (time > Duration.zero) {
          totals[user] = (totals[user] ?? Duration.zero) + time;
        }
      }
    }
    return totals;
  }

  int get peak => calls.fold(0, (p, c) => c.peak > p ? c.peak : p);

  VoiceCall? get longest => calls.isEmpty
      ? null
      : calls.reduce((a, b) =>
          (a.span.clip(window)?.duration ?? Duration.zero) >=
                  (b.span.clip(window)?.duration ?? Duration.zero)
              ? a
              : b);
}

/// A membership with no closing write whose window lapsed: a window this
/// short (rewritten every half minute, docs/voice-channel-members.md) ends
/// close to when its owner left, so it counts to there; a long one (four
/// hours, rewritten hourly) says nothing about when, so it counts to its last
/// write.
const _shortWindow = Duration(minutes: 10);

/// Two stretches with someone in the channel this close together are one
/// call: someone rejoining, or the last one out and the next one in.
const callGap = Duration(minutes: 1);

/// The calls in [roomId] that [records] (its call memberships' writes, in
/// any order) tell of, earliest first. [now] is the homeserver's time:
/// memberships still open at [now] are ongoing.
List<VoiceCall> callsFrom(
    String roomId, Iterable<CallMemberRecord> records, DateTime now) {
  final byDevice = <String, List<CallMemberRecord>>{};
  for (final record in records) {
    byDevice.putIfAbsent(record.stateKey, () => []).add(record);
  }

  final presence = <String, List<TimeSpan>>{};
  final activities = <String, Map<CallActivity, List<TimeSpan>>>{};
  final openUntilNow = <String>{};

  for (final writes in byDevice.values) {
    writes.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    _DeviceSession? open;

    void close(DateTime end, {bool ongoing = false}) {
      final session = open;
      if (session == null) return;
      open = null;
      if (!end.isAfter(session.start)) return;
      presence.putIfAbsent(session.sender, () => []).add(
            TimeSpan(session.start, end),
          );
      if (ongoing) openUntilNow.add(session.sender);
      final writes = session.writes;
      for (var i = 0; i < writes.length; i++) {
        final from = writes[i].sentAt.isBefore(session.start)
            ? session.start
            : writes[i].sentAt;
        final to = i + 1 < writes.length ? writes[i + 1].sentAt : end;
        if (!to.isAfter(from)) continue;
        for (final activity in _activitiesOf(writes[i])) {
          activities
              .putIfAbsent(session.sender, () => {})
              .putIfAbsent(activity, () => [])
              .add(TimeSpan(from, to));
        }
      }
    }

    for (final write in writes) {
      final content = write.content;
      if (content['application'] == null) {
        // Left (or the delayed leave fired).
        close(write.sentAt);
        continue;
      }
      final joinedAt =
          MatrixCallMembership.joinedAt(content, write.sentAt) ?? write.sentAt;
      final session = open;
      if (session != null && session.start != joinedAt) {
        // Joined again from this device: the earlier stay ended by then.
        final last = session.writes.last;
        final lapsed =
            MatrixCallMembership.expiresAt(last.content, last.sentAt);
        close(lapsed != null && lapsed.isBefore(joinedAt) ? lapsed : joinedAt);
      }
      (open ??= _DeviceSession(write.sender, joinedAt)).writes.add(write);
    }

    final session = open;
    if (session != null) {
      final last = session.writes.last;
      final expiry = MatrixCallMembership.expiresAt(last.content, last.sentAt);
      if (expiry == null || expiry.isAfter(now)) {
        close(now, ongoing: true);
      } else if (expiry.difference(last.sentAt) <= _shortWindow) {
        close(expiry);
      } else {
        close(last.sentAt);
      }
    }
  }

  // Everyone's stretches together, a call per run of them.
  final all = [for (final spans in presence.values) ...spans]
    ..sort((a, b) => a.start.compareTo(b.start));
  final blocks = <TimeSpan>[];
  for (final span in all) {
    if (blocks.isNotEmpty &&
        !span.start.isAfter(blocks.last.end.add(callGap))) {
      final last = blocks.removeLast();
      blocks.add(TimeSpan(
          last.start, span.end.isAfter(last.end) ? span.end : last.end));
    } else {
      blocks.add(span);
    }
  }

  return [
    for (final block in blocks)
      _callIn(roomId, block, presence, activities, openUntilNow, now),
  ];
}

VoiceCall _callIn(
    String roomId,
    TimeSpan block,
    Map<String, List<TimeSpan>> presence,
    Map<String, Map<CallActivity, List<TimeSpan>>> activities,
    Set<String> openUntilNow,
    DateTime now) {
  final inCall = <String, List<TimeSpan>>{};
  for (final entry in presence.entries) {
    final spans = _union([
      for (final span in entry.value)
        if (span.clip(block) case final part?) part,
    ]);
    if (spans.isNotEmpty) inCall[entry.key] = spans;
  }

  final did = <String, Map<CallActivity, List<TimeSpan>>>{};
  for (final entry in activities.entries) {
    for (final kind in entry.value.entries) {
      final spans = _union([
        for (final span in kind.value)
          if (span.clip(block) case final part?) part,
      ]);
      if (spans.isNotEmpty) {
        did.putIfAbsent(entry.key, () => {})[kind.key] = spans;
      }
    }
  }

  // The most at once: a sweep over everyone's joins and leaves.
  final edges = <(DateTime, int)>[
    for (final spans in inCall.values)
      for (final span in spans) ...[(span.start, 1), (span.end, -1)],
  ]..sort((a, b) {
      final byTime = a.$1.compareTo(b.$1);
      // A leave and a join at the same moment are not two at once.
      return byTime != 0 ? byTime : a.$2.compareTo(b.$2);
    });
  var here = 0, peak = 0;
  for (final (_, change) in edges) {
    here += change;
    if (here > peak) peak = here;
  }

  return VoiceCall(
    roomId: roomId,
    span: block,
    ongoing: !block.end.isBefore(now) && inCall.keys.any(openUntilNow.contains),
    presence: inCall,
    activities: did,
    peak: peak,
  );
}

/// [spans] as the fewest stretches that cover them, earliest first.
List<TimeSpan> _union(List<TimeSpan> spans) {
  spans.sort((a, b) => a.start.compareTo(b.start));
  final out = <TimeSpan>[];
  for (final span in spans) {
    if (out.isNotEmpty && !span.start.isAfter(out.last.end)) {
      final last = out.removeLast();
      out.add(TimeSpan(
          last.start, span.end.isAfter(last.end) ? span.end : last.end));
    } else {
      out.add(span);
    }
  }
  return out;
}

Set<CallActivity> _activitiesOf(CallMemberRecord write) {
  final content = write.content;
  final media = MatrixCallMembership.liveMediaOf(content);
  return {
    if (media.contains(LiveMedia.screen)) CallActivity.screen,
    if (media.contains(LiveMedia.camera)) CallActivity.camera,
    if (MatrixCallMembership.djPlayingOf(content) == true) CallActivity.dj,
  };
}

class _DeviceSession {
  _DeviceSession(this.sender, this.start);
  final String sender;
  final DateTime start;
  final List<CallMemberRecord> writes = [];
}
