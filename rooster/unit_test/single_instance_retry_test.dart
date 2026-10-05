// A launch that is not the first keeps trying to reach the running Rooster
// for a while (single_instance.dart), and a first launch tries once.
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/single_instance.dart';

void main() {
  const every = Duration(milliseconds: 5);

  test('a first launch tries once', () async {
    var attempts = 0;
    final reached = await SingleInstance.retry(() async {
      attempts++;
      return false;
    }, retryFor: Duration.zero, every: every);
    expect(reached, isFalse);
    expect(attempts, 1);
  });

  test('a later launch keeps trying until the running one answers', () async {
    var attempts = 0;
    final reached = await SingleInstance.retry(() async => ++attempts == 3,
        retryFor: const Duration(seconds: 5), every: every);
    expect(reached, isTrue);
    expect(attempts, 3);
  });

  test('and gives up once its time is over', () async {
    var attempts = 0;
    final reached = await SingleInstance.retry(() async {
      attempts++;
      return false;
    }, retryFor: const Duration(milliseconds: 50), every: every);
    expect(reached, isFalse);
    expect(attempts, greaterThan(1));
  });
}
