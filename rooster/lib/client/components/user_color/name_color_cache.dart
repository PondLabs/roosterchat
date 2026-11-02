import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:rooster/client/components/user_color/user_color_component.dart';
import 'package:rooster/utils/color_utils.dart';

/// Everyone's public name color (MSC4522), asked for when their name is drawn.
/// Homeservers never say when someone changes it, so a color older than
/// [maxAge] is asked for again the next time that name is drawn, and drawn as
/// it was until the answer comes.
// ponytail: unbounded, one entry per user drawn this session; evict if that
// ever shows up in memory.
class NameColorCache {
  NameColorCache(this.fetch, {DateTime Function()? now})
      : now = now ?? DateTime.now;

  /// The unstable profile field of MSC4522 (`m.color_preference`).
  static const String key = 'eu.she-a.color';
  static const Duration maxAge = Duration(minutes: 30);

  /// How soon a fetch that got no answer is tried again.
  static const Duration retryAfter = Duration(minutes: 1);
  static const int maxFetches = 4;

  /// The value of [key] in someone's profile, null when it is not set. Throws
  /// only when there is no answer (offline, a timeout, a server error); the
  /// color we had is kept and asked for again after [retryAfter].
  final Future<Object?> Function(String userId) fetch;
  final DateTime Function() now;

  final Map<String, ({NameColor? color, DateTime fetchedAt})> _entries = {};

  /// Waiting for a free fetch, the newest request last.
  final List<String> _queue = [];
  final Set<String> _fetching = {};

  final StreamController<String> _changed = StreamController.broadcast();

  /// The id of a user whose color changed.
  Stream<String> get onChanged => _changed.stream;

  NameColor? get(String userId) => _entries[userId]?.color;

  /// Everyone whose public color we know.
  Iterable<String> get coloredIds =>
      _entries.keys.where((id) => _entries[id]!.color != null);

  /// Fetches [userId]'s color unless it is fresh or already on its way.
  void request(String userId) {
    if (!userId.startsWith('@') || _fetching.contains(userId)) return;
    final entry = _entries[userId];
    if (entry != null && now().difference(entry.fetchedAt) < maxAge) return;
    _queue
      ..remove(userId)
      ..add(userId);
    _next();
  }

  /// Records [color] as [userId]'s as of now.
  void set(String userId, NameColor? color) {
    final previous = _entries[userId];
    _entries[userId] = (color: color, fetchedAt: now());
    if (previous?.color != color) _changed.add(userId);
  }

  void _next() {
    while (_fetching.length < maxFetches && _queue.isNotEmpty) {
      _load(_queue.removeLast());
    }
  }

  Future<void> _load(String userId) async {
    _fetching.add(userId);
    final askedAt = now();
    NameColor? color;
    var failed = false;
    try {
      color = parse(await fetch(userId));
    } catch (_) {
      // No answer (offline, timeout, 5xx, 429): keep what we had, ask again
      // soon.
      failed = true;
    }
    _fetching.remove(userId);
    // A color set while this one was on its way is newer.
    if (_entries[userId]?.fetchedAt.isAfter(askedAt) != true) {
      if (failed) {
        _entries[userId] = (
          color: _entries[userId]?.color,
          fetchedAt: now().subtract(maxAge - retryAfter),
        );
      } else {
        set(userId, color);
      }
    }
    _next();
  }

  static final RegExp _hex =
      RegExp(r'^#?([0-9a-f]{3}|[0-9a-f]{6})$', caseSensitive: false);

  /// The color in a field value, `{"on_dark": "#rrggbb", "on_light":
  /// "#rrggbb"}` (`#rgb` too). A variant that is missing or not a color takes
  /// the other one.
  static NameColor? parse(Object? value) {
    if (value is! Map) return null;
    final onDark = _parseHex(value['on_dark']);
    final onLight = _parseHex(value['on_light']);
    if (onDark == null && onLight == null) return null;
    return NameColor(onDark: onDark ?? onLight!, onLight: onLight ?? onDark!);
  }

  static Map<String, String> serialize(NameColor color) => {
        'on_dark': color.onDark.toHexCode(),
        'on_light': color.onLight.toHexCode(),
      };

  static Color? _parseHex(Object? value) {
    final digits = value is String ? _hex.firstMatch(value)?.group(1) : null;
    if (digits == null) return null;
    final rgb = digits.length == 3
        ? digits.split('').map((digit) => '$digit$digit').join()
        : digits;
    return Color(0xff000000 | int.parse(rgb, radix: 16));
  }
}
