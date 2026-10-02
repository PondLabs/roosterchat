// The sounds a voice room plays when someone starts or stops sharing their
// screen, or turns their camera on or off. Every client plays them for itself
// when it sees the change, so everyone in the room hears them, the one who
// started included.
//
// Plain logic, fed what is live now: whatever event told the session about
// it (a publish, an unmute, a reconnect that rebuilt everything), a change
// plays only once. A screen share or camera that ends because its owner left
// the call makes no sound of its own: the leave sound is theirs.

/// Something that has a sound when it starts and when it stops.
enum ShareCue { screenShare, camera }

/// A sound the room plays: a screen share or camera starting or stopping.
enum ShareSound { screenShareStarted, cameraOn, screenShareStopped, cameraOff }

class ShareCueTracker {
  ShareCueTracker({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// What was live at the last update: `<participant>|<cue>`.
  Set<String> _live = {};
  bool _seeded = false;
  DateTime? _quietUntil;
  final Map<ShareSound, DateTime> _lastPlayed = {};

  /// Shortest gap between two of the same sound: several people starting (or
  /// stopping) at once make one.
  static const minGap = Duration(seconds: 1);

  /// How long after a reconnect nothing plays: LiveKit rebuilds the room and
  /// republishes what was already live, which is no start.
  static const reconnectQuiet = Duration(seconds: 5);

  /// Takes what is live now, as `participant identity -> cues` for everyone in
  /// the call (an empty set for who shares nothing), and gives the sounds to
  /// play: one per kind that someone started since the last update, and one
  /// per kind that someone still in the call stopped. The first update only
  /// learns what is there (joining a call where people already share is no
  /// start), and so does any update with [quiet] set or inside the quiet time
  /// after [reconnected].
  List<ShareSound> update(Map<String, Set<ShareCue>> live,
      {bool quiet = false}) {
    final now = _now();
    final keys = {
      for (final MapEntry(key: who, value: cues) in live.entries)
        for (final cue in cues) '$who|${cue.name}',
    };
    final started = keys.difference(_live);
    final stopped = _live.difference(keys).where(
        (key) => live.containsKey(key.substring(0, key.lastIndexOf('|'))));
    _live = keys;
    final silent = !_seeded ||
        quiet ||
        (_quietUntil != null && now.isBefore(_quietUntil!));
    _seeded = true;
    if (silent) return const [];

    bool any(Iterable<String> keys, ShareCue cue) =>
        keys.any((key) => key.endsWith('|${cue.name}'));
    final sounds = <ShareSound>[];
    void play(ShareSound sound) {
      final last = _lastPlayed[sound];
      if (last != null && now.difference(last) < minGap) return;
      _lastPlayed[sound] = now;
      sounds.add(sound);
    }

    if (any(started, ShareCue.screenShare)) {
      play(ShareSound.screenShareStarted);
    }
    if (any(started, ShareCue.camera)) play(ShareSound.cameraOn);
    if (any(stopped, ShareCue.screenShare)) {
      play(ShareSound.screenShareStopped);
    }
    if (any(stopped, ShareCue.camera)) play(ShareSound.cameraOff);
    return sounds;
  }

  /// The room was rebuilt after a reconnect: what comes back in the next
  /// moments was already live before.
  void reconnected() => _quietUntil = _now().add(reconnectQuiet);
}
