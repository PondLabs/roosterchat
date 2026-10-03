// Keeps the state listed in our own call membership (issue #9) in step with
// what we publish and whether we have silenced ourselves, without hammering
// the homeserver: state writes share the message rate limit (Synapse's
// default is 0.2/s with a burst of 10).
import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:rooster/client/components/activities/activities_component.dart';
import 'package:rooster/debug/log.dart';

/// What our call membership advertises about us. Written as one value, since
/// every write rewrites the whole state event and two writers would clobber
/// each other.
class CallMembershipState {
  const CallMembershipState({
    this.media = const {},
    this.voice = const {},
    this.away = false,
    this.dj,
    this.unguarded = false,
  });

  /// What we publish: screen share, camera.
  final Set<LiveMedia> media;

  /// How we have silenced ourselves: muted, deafened.
  final Set<VoiceState> voice;

  /// Whether we have been away from the machine long enough to count as
  /// away. Changes at most twice an hour or so, which the debounce below
  /// absorbs along with everything else.
  final bool away;

  /// Null when we aren't the DJ, otherwise whether our music is playing.
  final bool? dj;

  /// No delayed leave backs what is advertised here: readers stop believing
  /// it once it has not been written again for a while (see
  /// MatrixCallMembership.unguardedKey).
  final bool unguarded;

  static const _media = SetEquality<LiveMedia>();
  static const _voice = SetEquality<VoiceState>();

  @override
  bool operator ==(Object other) =>
      other is CallMembershipState &&
      _media.equals(media, other.media) &&
      _voice.equals(voice, other.voice) &&
      away == other.away &&
      dj == other.dj &&
      unguarded == other.unguarded;

  @override
  int get hashCode =>
      Object.hash(_media.hash(media), _voice.hash(voice), away, dj, unguarded);

  @override
  String toString() =>
      "CallMembershipState(media: $media, voice: $voice, away: $away, "
      "dj: $dj, unguarded: $unguarded)";
}

class CallMembershipPublisher {
  CallMembershipPublisher({
    required Future<void> Function(CallMembershipState state) write,
    this.debounce = const Duration(milliseconds: 750),
    this.minInterval = const Duration(seconds: 2),
    this.maxBackoff = const Duration(minutes: 1),
  }) : _write = write;

  final Future<void> Function(CallMembershipState state) _write;

  /// How long a value must stay unchanged before it is written.
  final Duration debounce;

  /// Least time between two writes; doubles after each failed write, up to
  /// [maxBackoff].
  final Duration minInterval;
  final Duration maxBackoff;

  /// The join write lists nothing.
  CallMembershipState _written = const CallMembershipState();
  CallMembershipState _desired = const CallMembershipState();
  Timer? _debounceTimer;
  Timer? _cooldownTimer;
  Future<void>? _inFlight;
  int _failures = 0;
  bool _stopped = false;

  /// A write was asked for even with nothing changed (see [rewrite]).
  bool _rewrite = false;

  /// What we advertise now. Written once it has stayed the same for
  /// [debounce], one write at a time and at most one per [minInterval];
  /// a value equal to the last one written isn't written again.
  void update(CallMembershipState state) {
    if (_stopped) return;
    _desired = state;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      _flush();
    });
  }

  /// Writes what we advertise again although it has not changed: every
  /// write pushes the membership's expiry out, and it lapses for everyone if
  /// nothing does. Waits its turn like any other write, and one going out
  /// anyway does for it.
  void rewrite() {
    if (_stopped) return;
    _rewrite = true;
    _flush();
  }

  void _flush() {
    if (_stopped ||
        _debounceTimer != null ||
        _inFlight != null ||
        _cooldownTimer != null) {
      return;
    }
    if (_desired == _written && !_rewrite) return;

    final sending = _send(_desired);
    _inFlight = sending;
    sending.whenComplete(() {
      if (identical(_inFlight, sending)) _inFlight = null;
    });
  }

  Future<void> _send(CallMembershipState state) async {
    var wait = minInterval;
    try {
      await _write(state);
      _written = state;
      _rewrite = false;
      _failures = 0;
    } catch (e) {
      _failures++;
      Log.w("Could not publish call membership state (attempt $_failures): $e");
      final backoff = minInterval * pow(2, _failures - 1).toInt();
      wait = backoff > maxBackoff ? maxBackoff : backoff;
    }

    if (_stopped) return;
    _cooldownTimer = Timer(wait, () {
      _cooldownTimer = null;
      _flush();
    });
  }

  /// Stops publishing: drops what is pending and waits for the write in
  /// flight, so nothing lands after the caller clears the membership.
  Future<void> stop() async {
    _stopped = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    await _inFlight;
  }
}
