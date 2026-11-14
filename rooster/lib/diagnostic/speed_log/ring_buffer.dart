/// The newest [capacity] items, oldest first. Adding to a full buffer drops
/// the oldest item. The storage is one fixed-length list allocated up front,
/// so the speed log costs the same memory after a week as after a minute.
class RingBuffer<T> {
  RingBuffer(this.capacity)
      : assert(capacity > 0),
        _items = List<T?>.filled(capacity, null);

  final int capacity;
  final List<T?> _items;
  int _next = 0;
  int _length = 0;

  int get length => _length;

  void add(T item) {
    _items[_next] = item;
    _next = (_next + 1) % capacity;
    if (_length < capacity) _length++;
  }

  /// A copy of the items, oldest first.
  List<T> toList() {
    final start = (_next - _length) % capacity;
    return List<T>.generate(_length, (i) => _items[(start + i) % capacity] as T,
        growable: false);
  }

  void clear() {
    _items.fillRange(0, capacity, null);
    _next = 0;
    _length = 0;
  }

  /// The storage itself, for tests that check it never grows.
  List<T?> get debugStorage => _items;
}
