// Away: nobody has touched this machine for a quarter of an hour. It is the
// third thing a status dot can say, between online and offline, and it is
// about the person rather than the app — someone can be sitting in a voice
// channel all evening with Rooster behind a game, and someone can leave the
// room with it in front of them.
//
// [systemIdleTime] is what knows that, where the platform can tell us. Where
// it cannot (mobile, and a browser without idle detection permission) this
// falls back to how long the app has been in the background, which is the
// nearest thing those platforms have.
import 'dart:async';

import 'package:rooster/client/components/user_presence/user_presence_component.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/idle/system_idle.dart';
import 'package:flutter/widgets.dart';

class UserIdleWatcher {
  UserIdleWatcher({
    Future<Duration?> Function()? idleTime,
    Future<void> Function(UserPresenceStatus status)? publish,
    this.threshold = const Duration(minutes: 15),
    this.pollInterval = const Duration(seconds: 30),
    DateTime Function()? now,
  })  : _idleTime = idleTime ?? systemIdleTime,
        _publish = publish ?? _setStatusOnEveryClient,
        _now = now ?? DateTime.now {
    isAway.addListener(_updateStatus);
  }

  static final UserIdleWatcher instance = UserIdleWatcher();

  final Future<Duration?> Function() _idleTime;
  final Future<void> Function(UserPresenceStatus status) _publish;
  final DateTime Function() _now;

  /// How long someone has to be away from their machine to count as away.
  final Duration threshold;

  /// Idle time is cheap to read, but not free: this is well under
  /// [threshold], so crossing it is noticed promptly, and far longer than
  /// any of the calls behind [systemIdleTime] take.
  final Duration pollInterval;

  /// Whether the person at this machine has been away from it for
  /// [threshold]. The voice session puts this in our call membership, so
  /// people in the channel see it even on a homeserver that shares no
  /// presence, and the presence component publishes it as our status.
  final ValueNotifier<bool> isAway = ValueNotifier(false);

  /// What we show everyone: the status chosen from the menu on our own dot,
  /// with online turning to away while [isAway]. Away and invisible
  /// ([UserPresenceStatus.offline]) hold however active we are.
  final ValueNotifier<UserPresenceStatus> status =
      ValueNotifier(UserPresenceStatus.online);

  UserPresenceStatus _chosen = UserPresenceStatus.online;

  /// The statuses the menu offers.
  static const choices = [
    UserPresenceStatus.online,
    UserPresenceStatus.unavailable,
    UserPresenceStatus.offline,
  ];

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  DateTime? _hiddenSince;
  bool _isInit = false;
  bool _polling = false;
  UserPresenceStatus? _published;

  void init() {
    if (_isInit) return;
    _isInit = true;

    final saved =
        UserPresenceStatus.values.asNameMap()[preferences.presenceStatus.value];
    if (saved != null && choices.contains(saved)) _chosen = saved;
    _updateStatus();

    _lifecycle = AppLifecycleListener(
      onShow: _foreground,
      onResume: _foreground,
      onHide: _background,
      onPause: _background,
    );

    _timer = Timer.periodic(pollInterval, (_) => unawaited(poll()));
    unawaited(poll());
  }

  void _foreground() {
    _hiddenSince = null;
    unawaited(poll());
  }

  void _background() => _hiddenSince ??= _now();

  /// When the app went into the background, for the fallback above. The
  /// tests set it: there is no [AppLifecycleListener] to drive it there.
  set hiddenSince(DateTime? at) => _hiddenSince = at;

  /// Reads the idle time and, when that changes whether we are away, says so.
  /// Public for the tests, which drive it directly rather than on a timer.
  Future<void> poll() async {
    if (_polling) return;
    _polling = true;

    try {
      final idle = await _idleTime();
      final away = (idle ?? _hiddenFor()) >= threshold;

      if (away != isAway.value) isAway.value = away;

      await _publishStatus();
    } catch (e) {
      Log.w("Could not tell whether we are away: $e");
    } finally {
      _polling = false;
    }
  }

  /// Shows [choice] from now on, and remembers it across restarts.
  Future<void> choose(UserPresenceStatus choice) async {
    _chosen = choice;
    await preferences.presenceStatus.set(choice.name);
    try {
      await _publishStatus();
    } catch (e) {
      Log.w("Could not set our status: $e");
    }
  }

  void _updateStatus() =>
      status.value = _chosen == UserPresenceStatus.online && isAway.value
          ? UserPresenceStatus.unavailable
          : _chosen;

  Future<void> _publishStatus() async {
    _updateStatus();
    final next = status.value;

    // Recorded after the write, not before: a write that failed is worth
    // trying again on the next poll.
    if (next != _published) {
      await _publish(next);
      _published = next;
    }
  }

  Duration _hiddenFor() {
    final since = _hiddenSince;
    return since == null ? Duration.zero : _now().difference(since);
  }

  static Future<void> _setStatusOnEveryClient(UserPresenceStatus status) async {
    final manager = clientManager;
    if (manager == null) return;
    for (final client in manager.clients) {
      if (!client.isLoggedIn()) continue;
      final component = client.getComponent<UserPresenceComponent>();
      await component?.setStatus(status);
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _isInit = false;
  }
}
