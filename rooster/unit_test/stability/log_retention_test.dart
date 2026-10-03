import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/debug/log.dart';

void main() {
  tearDown(() => Log.log.clear());

  test('daily logging retains only a bounded recent history', () {
    Log.log.clear();
    for (var i = 0; i < 20000; i++) {
      Log.add(LogEntry(LogType.info, 'sync $i'));
    }
    expect(Log.log.length, lessThanOrEqualTo(2000));
    expect(Log.log.last.rawContent, 'sync 19999');
    expect(Log.log.first.rawContent, 'sync 18000');
  });

  test('identical consecutive entries are still coalesced', () {
    Log.log.clear();
    for (var i = 0; i < 3000; i++) {
      Log.add(LogEntry(LogType.warning, 'reconnecting'));
    }
    expect(Log.log.length, 1);
    expect(Log.log.single.count, 3000);
  });
}
