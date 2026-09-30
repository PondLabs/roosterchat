// Our call membership content (org.matrix.msc3401.call.member) beyond what the
// MatrixRTC proposals define: which streams a member publishes and whether
// they have silenced themselves, so the voice channel list can show who is
// live, muted or deafened to people outside the call (issue #9).
// Pure Dart. See docs/research/issue-9-live-badge-voice-list.md.
import 'dart:async';

import 'package:cockhouse/client/components/activities/activities_component.dart';
import 'package:cockhouse/client/matrix/homeserver_clock.dart';

class MatrixCallMembership {
  /// Lists what the member publishes, e.g. `["screen", "camera"]`. Other
  /// clients ignore keys they don't know.
  static const liveMediaKey = 'chat.commet.streams';

  /// Lists how the member has silenced themselves, e.g. `["muted"]` or
  /// `["muted", "deafened"]`. An absent key means the member's client does
  /// not report it, which is not the same as being unmuted.
  static const voiceStateKey = 'chat.commet.voice_state';

  /// Whether the member has been away from their machine long enough to
  /// count as away. In the membership rather than left to Matrix presence:
  /// plenty of homeservers (matrix.org among them) share no presence at all,
  /// and someone sitting in a voice channel is exactly who you want to know
  /// this about.
  static const awayKey = 'chat.commet.away';

  /// How long a membership lasts from its join time, the MatrixRTC default.
  static const lifetime = Duration(hours: 4);

  /// Its owner writes it again, pushing the expiry [lifetime] past then, once
  /// this much of it is left: an hour after each write. Pushed out only in
  /// its last hour, a membership lapsed for everyone whose clock ran an hour
  /// ahead of its owner's, or whenever one write failed.
  static const refreshWhenLeft = Duration(hours: 3);

  /// What [content] reports the member publishing. Unknown values and
  /// malformed content are ignored.
  static Set<LiveMedia> liveMediaOf(Map<String, Object?> content) {
    final value = content[liveMediaKey];
    if (value is! List) return const {};
    return {
      for (final media in LiveMedia.values)
        if (value.contains(media.name)) media,
    };
  }

  /// How [content] reports the member having silenced themselves. Unknown
  /// values and malformed content are ignored, and `deafened` on its own is
  /// read as muted too, since deafening turns the microphone off.
  static Set<VoiceState> voiceStateOf(Map<String, Object?> content) {
    final value = content[voiceStateKey];
    if (value is! List) return const {};
    final state = {
      for (final flag in VoiceState.values)
        if (value.contains(flag.name)) flag,
    };
    if (state.contains(VoiceState.deafened)) state.add(VoiceState.muted);
    return state;
  }

  /// Whether [content] says its owner is away from their machine. Anything
  /// else, a client that does not report it included, reads as present.
  static bool isAway(Map<String, Object?> content) => content[awayKey] == true;

  /// When the member joined: `created_ts` once the membership has been
  /// rewritten, otherwise when it was sent ([sentAt]).
  static DateTime? joinedAt(Map<String, Object?> content, DateTime? sentAt) {
    final created = content['created_ts'];
    if (created is int) return DateTime.fromMillisecondsSinceEpoch(created);
    return sentAt;
  }

  /// When the membership's `expires` window, counted from its join time like
  /// MatrixRTC clients do, closes. Null when it never does: no `expires`, or
  /// stripped state, which carries no [sentAt].
  static DateTime? expiresAt(Map<String, Object?> content, DateTime? sentAt) {
    final expires = content['expires'];
    if (expires is! int || sentAt == null) return null;
    return joinedAt(content, sentAt)!.add(Duration(milliseconds: expires));
  }

  /// Whether the membership's `expires` window has passed at [now]. Stripped
  /// state carries no [sentAt] and is assumed live.
  static bool isExpired(
      Map<String, Object?> content, DateTime? sentAt, DateTime now) {
    final expiry = expiresAt(content, sentAt);
    return expiry != null && now.isAfter(expiry);
  }

  /// Whether our own membership, [content] sent at [sentAt], is due to be
  /// written again at [now] to keep it from lapsing (see [refreshWhenLeft]).
  /// Also once it has lapsed: we are still in the call.
  static bool needsRefresh(
      Map<String, Object?> content, DateTime? sentAt, DateTime now) {
    final expiry = expiresAt(content, sentAt);
    return expiry != null && expiry.difference(now) <= refreshWhenLeft;
  }

  /// The earliest of [expiries] still ahead of [now], when the list of who is
  /// in the call next changes without any event arriving: nothing is sent
  /// when a membership lapses, so whoever lists them has to look again then.
  static DateTime? nextExpiry(Iterable<DateTime?> expiries, DateTime now) {
    DateTime? next;
    for (final expiry in expiries) {
      // Already lapsed means not listed; one lapsing right now still is.
      if (expiry == null || expiry.isBefore(now)) continue;
      if (next == null || expiry.isBefore(next)) next = expiry;
    }
    return next;
  }

  /// [current] rewritten to list [media], [voiceState] and [away]. Every
  /// other key is kept, the join time is recorded in `created_ts` (without it
  /// other clients take the rewrite for a new join, re-key, and reorder the
  /// oldest_membership focus choice), and the expiry moves [lifetime] past
  /// [now].
  static Map<String, Object?> withPublishedState(Map<String, Object?> current,
      {required Set<LiveMedia> media,
      required Set<VoiceState> voiceState,
      required DateTime joinedAt,
      required DateTime now,
      bool away = false}) {
    return {
      ...current,
      'created_ts': joinedAt.millisecondsSinceEpoch,
      'expires':
          now.difference(joinedAt).inMilliseconds + lifetime.inMilliseconds,
      awayKey: away,
      liveMediaKey: [
        for (final m in LiveMedia.values)
          if (media.contains(m)) m.name,
      ],
      voiceStateKey: [
        for (final flag in VoiceState.values)
          if (voiceState.contains(flag)) flag.name,
      ],
    };
  }
}

/// Tells a list of who is in a call to look again when the next membership
/// in it lapses. Without it a member whose client died without leaving (no
/// delayed leave on their homeserver, or a leave that never got through)
/// stayed listed long past their `expires`, until some other membership
/// change happened to come by.
class MembershipLapseTimer {
  /// [now] is the homeserver's time, which memberships lapse by.
  MembershipLapseTimer(this.onLapse, {DateTime Function()? now})
      : _now = now ?? HomeserverClock.instance.now;

  final void Function() onLapse;
  final DateTime Function() _now;

  Timer? _timer;
  DateTime? _at;

  /// Fires [onLapse] just after [at], replacing what was scheduled before;
  /// null cancels it.
  void schedule(DateTime? at) {
    if (at == _at) return;
    _timer?.cancel();
    _timer = null;
    _at = at;
    if (at == null) return;

    // Just after: a membership is still live at the very moment it expires.
    final delay = at.difference(_now()) + const Duration(milliseconds: 1);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _timer = null;
      _at = null;
      onLapse();
    });
  }

  void cancel() => schedule(null);
}
