import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/main.dart';
import 'package:rooster/utils/background_tasks/background_task_manager.dart';
import 'package:rooster/utils/custom_safe_area.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:rooster/utils/in_memory_cache.dart';
import 'package:rooster/utils/text_scale_changer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // The analyzer does not recognize nested unit_test directories as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  testWidgets('cache stays bounded during a large presence burst',
      (tester) async {
    final cache = InMemoryCache<int>(limit: 50);
    addTearDown(cache.dispose);
    final removed = <String>[];
    final sub = cache.onRemove.listen(removed.add);
    for (var i = 0; i < 10000; i++) {
      cache.put('$i', i);
    }
    await tester.pump();
    expect(cache.get('0'), isNull);
    expect(cache.get('9949'), isNull);
    expect(cache.get('9950'), 9950);
    expect(cache.get('9999'), 9999);
    expect(removed.length, 9950);
    unawaited(sub.cancel());
    cache.dispose();
    await tester.pump();
  });

  testWidgets('closing a task while its future runs does not emit after close',
      (tester) async {
    final pending = Completer<BackgroundTaskStatus>();
    final task = AsyncTask(() => pending.future, 'upload');
    task.dispose();
    pending.complete(BackgroundTaskStatus.completed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired cache entries notify once and shutdown cancels polling',
      (tester) async {
    final cache = InMemoryCache<int>(
        maxRetention: Duration.zero,
        pollFrequency: const Duration(milliseconds: 10));
    final removed = <String>[];
    cache.onRemove.listen(removed.add);
    cache.put('expired', 1);
    expect(cache.get('expired'), isNull);
    unawaited(cache.clean());
    await tester.pump();
    expect(removed, ['expired']);
    cache.dispose();
    cache.dispose();
    cache.put('after-close', 2);
    await tester.pump(const Duration(seconds: 1));
    expect(cache.get('after-close'), isNull);
    expect(removed, ['expired']);
  });

  testWidgets('closing a completed task cancels its removal timer',
      (tester) async {
    final task =
        AsyncTask(() async => BackgroundTaskStatus.completed, 'upload');
    await tester.pump();
    task.dispose();
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('text scale changes after unmount do not call setState',
      (tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pumpWidget(const MaterialApp(
        home: TextScaleChanger(child: Text('chat')),
      ));
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await preferences.textScale.set(1.2);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('safe area releases the global focus subscription after unmount',
      (tester) async {
    expect(EventBus.onTextFieldFocused.hasListener, isFalse);
    for (var i = 0; i < 30; i++) {
      await tester.pumpWidget(const MaterialApp(
        home: CustomSafeArea(child: Text('chat')),
      ));
      expect(EventBus.onTextFieldFocused.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(EventBus.onTextFieldFocused.hasListener, isFalse);
    }
  });
}
