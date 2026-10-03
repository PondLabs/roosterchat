import 'dart:async';

class InMemoryCache<T> {
  InMemoryCache({
    this.limit = 50,
    this.maxRetention = const Duration(minutes: 10),
    this.pollFrequency = const Duration(minutes: 2),
  }) {
    if (limit < 1 ||
        maxRetention.isNegative ||
        pollFrequency <= Duration.zero) {
      throw ArgumentError(
          'Cache capacity and polling interval must be positive');
    }
    _timer = Timer.periodic(pollFrequency, (_) => clean());
  }

  late final Timer _timer;
  final int limit;
  final Duration maxRetention;
  final Duration pollFrequency;

  final StreamController<String> _controller = StreamController.broadcast();
  bool _disposed = false;

  Stream<String> get onRemove => _controller.stream;

  final Map<String, (T, DateTime)> _cache = {};

  void put(String key, T value) {
    if (_disposed) return;
    // Keep the most recently written entries when capacity is reached.
    _cache.remove(key);
    _cache[key] = (value, DateTime.now());
    while (_cache.length > limit) {
      _remove(_cache.keys.first);
    }
  }

  T? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.$2) >= maxRetention) {
      _remove(key);
      return null;
    }
    return entry.$1;
  }

  void _remove(String key) {
    _cache.remove(key);
    _controller.add(key);
  }

  Future<void> clean() async {
    if (_disposed) return;
    final now = DateTime.now();
    for (final key in _cache.keys.toList()) {
      if (now.difference(_cache[key]!.$2) >= maxRetention) _remove(key);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer.cancel();
    _cache.clear();
    unawaited(_controller.close());
  }
}
