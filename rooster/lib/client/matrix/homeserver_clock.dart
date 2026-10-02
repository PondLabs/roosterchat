// What time it is on the homeserver. Call memberships lapse by its clock:
// their join time is its origin_server_ts, and their window runs from there.
// This machine's clock can be hours out (a Windows clock reading a dual
// boot's UTC hardware clock as local time runs three hours ahead in Brazil),
// and read against it, everyone who had been in a voice channel for a while
// vanished from the list while they were still in it.
// See docs/voice-channel-members.md.
import 'dart:async';

import 'package:rooster/debug/log.dart';
import 'package:matrix/matrix.dart';

class HomeserverClock {
  HomeserverClock({DateTime Function()? localNow, Duration Function()? steady})
      : _localNow = localNow ?? DateTime.now,
        _steady = steady ?? _stopwatch();

  static Duration Function() _stopwatch() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  /// The app's. Every account's syncs set it: homeservers keep good time,
  /// and it is this machine's clock they correct.
  static final HomeserverClock instance = HomeserverClock();

  /// How long a reading is kept over later ones that say it is earlier: a
  /// reading is only ever late (the time it took to answer, to process the
  /// sync) or back-dated (a bridge's message, sent with its original time),
  /// so the one furthest ahead is the best; unless the homeserver's clock
  /// itself was set back, which one this old gives way to.
  static const _readingLifetime = Duration(minutes: 5);

  final DateTime Function() _localNow;

  /// A clock that only ever runs forward, at the same pace whatever this
  /// machine's clock is set to.
  final Duration Function() _steady;

  /// The homeserver's time at the reading kept, and [_steady] then.
  DateTime? _readAt;
  Duration _readOn = Duration.zero;

  /// What was last logged about this machine's clock.
  Duration _loggedOffset = Duration.zero;

  /// How far a reading has to move [now] for [onCorrected].
  static const _notable = Duration(seconds: 30);

  final StreamController<void> _corrected = StreamController.broadcast();

  /// A reading moved [now] by more than half a minute: the first one, on a
  /// machine whose clock is out, or the first after a sleep. Whoever read
  /// memberships by the time as it was reads them again: nothing else might
  /// come by for an hour.
  Stream<void> get onCorrected => _corrected.stream;

  /// The homeserver's time now: the reading kept, moved on by [_steady], so
  /// setting this machine's clock does not move it. This machine's clock
  /// until the homeserver has said anything.
  DateTime now() {
    final readAt = _readAt;
    if (readAt == null) return _localNow();
    return readAt.add(_steady() - _readOn);
  }

  /// How far the homeserver's clock is ahead of this machine's.
  Duration get offset => now().difference(_localNow());

  /// Reads the time off a sync that just came in. The homeserver gives every
  /// event it serves its age, and one sent from it has its clock in
  /// origin_server_ts, so the two add up to its time when it answered.
  /// Events from other homeservers carry their own clock, and local echoes
  /// no age.
  void readSync(SyncUpdate sync, {required String homeserver}) {
    DateTime? serverTime;
    for (final room in sync.rooms?.join?.values ?? const <JoinedRoomUpdate>[]) {
      for (final event in [...?room.state, ...?room.timeline?.events]) {
        final age = event.unsigned?['age'];
        if (age is! int || age < 0) continue;
        if (event.senderId.domain != homeserver) continue;
        final time = event.originServerTs.add(Duration(milliseconds: age));
        if (serverTime == null || time.isAfter(serverTime)) serverTime = time;
      }
    }
    if (serverTime == null) return;

    final before = now();
    final fresh = _readAt != null && _steady() - _readOn < _readingLifetime;
    if (fresh && !serverTime.isAfter(before)) return;
    _readAt = serverTime;
    _readOn = _steady();
    if (serverTime.difference(before).abs() > _notable) _corrected.add(null);

    if ((offset - _loggedOffset).abs() > const Duration(minutes: 1)) {
      _loggedOffset = offset;
      final side = offset.isNegative ? "ahead of" : "behind";
      Log.i("This machine's clock is ${offset.abs()} $side $homeserver's");
    }
  }
}
