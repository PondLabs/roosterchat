import 'package:rooster/diagnostic/speed_log/ring_buffer.dart';
import 'package:test/test.dart';

void main() {
  test('keeps only the newest items and never grows', () {
    const capacity = 64;
    final buffer = RingBuffer<int>(capacity);
    final storage = buffer.debugStorage;

    for (var i = 0; i < capacity * 10; i++) {
      buffer.add(i);
      expect(buffer.length, lessThanOrEqualTo(capacity));
      expect(identical(buffer.debugStorage, storage), isTrue);
      expect(buffer.debugStorage.length, capacity);
    }

    expect(buffer.length, capacity);
    expect(buffer.toList(),
        List.generate(capacity, (i) => capacity * 9 + i)); // oldest first
  });

  test('lists what it holds before it is full, oldest first', () {
    final buffer = RingBuffer<String>(3)
      ..add('a')
      ..add('b');
    expect(buffer.toList(), ['a', 'b']);
    buffer
      ..add('c')
      ..add('d');
    expect(buffer.toList(), ['b', 'c', 'd']);
    buffer.clear();
    expect(buffer.toList(), isEmpty);
  });
}
