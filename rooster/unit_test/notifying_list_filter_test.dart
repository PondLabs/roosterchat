import 'dart:async';

import 'package:rooster/utils/notifying_list.dart';
import 'package:rooster/utils/notifying_list_filter.dart';
import 'package:test/test.dart';

/// An item compared by value, like a room is compared by its id.
class _Item {
  _Item(this.id);
  final int id;

  @override
  bool operator ==(Object other) => other is _Item && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

void main() {
  test('a filter change keeps the list in step with the filter', () {
    final base = NotifyingList<_Item>.empty(growable: true);
    for (var i = 0; i < 10; i++) {
      base.add(_Item(i));
    }
    var even = true;
    final changed = StreamController<void>.broadcast(sync: true);
    final filter = NotifyingListFilter(base,
        where: (item) => item.id.isEven == even,
        onFilterParamsChanged: [changed.stream]);
    final removed = <int>[];
    final added = <int>[];
    filter.onRemove.listen((item) => removed.add(item.id));
    filter.onAdd.listen((item) => added.add(item.id));

    expect([for (final item in filter) item.id], [0, 2, 4, 6, 8]);

    even = false;
    changed.add(null);

    expect([for (final item in filter) item.id], [1, 3, 5, 7, 9]);
    expect(removed, [0, 2, 4, 6, 8]);
    expect(added, [1, 3, 5, 7, 9]);

    changed.add(null);
    expect(filter.length, 5, reason: 'nothing changed, nothing is added');
  });

  test('a filter change costs no more per item in a long list', () {
    // The room list's filters rerun on every update to any room in a space.
    Duration cost(int count) {
      final base = NotifyingList<_Item>.empty(growable: true);
      for (var i = 0; i < count; i++) {
        base.add(_Item(i));
      }
      final changed = StreamController<void>.broadcast(sync: true);
      NotifyingListFilter(base,
          where: (item) => item.id.isEven,
          onFilterParamsChanged: [changed.stream]);
      final clock = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        changed.add(null);
      }
      return clock.elapsed ~/ 5;
    }

    cost(1000);
    cost(8000); // warm up
    final small = cost(1000);
    final large = cost(8000);
    // ignore: avoid_print
    print('filter change: 1000 items $small, 8000 items $large');
    // 8 times the items: linear work grows about 8 times, comparing every
    // item with every other 64 times.
    expect(large.inMicroseconds, lessThan(small.inMicroseconds * 20 + 500));
  });
}
