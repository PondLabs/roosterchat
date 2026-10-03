import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/components/user_presence/user_idle_watcher.dart';
import 'package:rooster/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/diagnostic/mocks/matrix_client_component_mocks.dart';
import 'package:rooster/generated/l10n.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:rooster/ui/pages/developer/benchmarks/benchmark_utils.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../../integration_test/stability_memory.dart';

// The workload exercises the real Matrix event conversion and chat widgets.
// Storage and networking are excluded so measurements have repeatable input.
class _Database implements matrix.DatabaseApi {
  @override
  Future<List<matrix.Event>> getUnimportantRoomEventStatesForRoom(
          List<String> types, matrix.Room room) async =>
      [];

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Map<String, Object?>> runTimelineWorkload(WidgetTester tester,
    {int cycles = 5}) async {
  final samples = <int?>[];
  final client = MatrixClient(identifier: 'stability', database: _Database());
  client.mockComponents();
  client.self = MatrixProfile(client,
      matrix.Profile(userId: '@benchy:example.com', displayName: 'Benchy'));
  UserIdleWatcher.instance.dispose();
  final room = client.createRoomWithData();
  try {
    for (final mode in ['desktop', 'mobile']) {
      await preferences.layoutOverride.set(mode);
      await tester.binding.setSurfaceSize(
          mode == 'mobile' ? const Size(390, 844) : const Size(1440, 900));
      for (var cycle = 0; cycle < cycles; cycle++) {
        final timeline = room.getBenchmarkTimeline();
        await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: Scaffold(body: RoomTimelineWidgetView(timeline: timeline)),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final list = find.byType(Scrollable);
        expect(list, findsOneWidget);
        for (var i = 0; i < 12; i++) {
          await tester.drag(list, const Offset(0, 400));
          await tester.pump(const Duration(milliseconds: 16));
        }
        for (var i = 0; i < 12; i++) {
          await tester.drag(list, const Offset(0, -400));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        expect(EventBus.jumpToEvent.hasListener, isFalse);
        expect(timeline.onEventAdded.hasListener, isFalse);
        expect(timeline.onChange.hasListener, isFalse);
        expect(timeline.onRemove.hasListener, isFalse);
        await timeline.close();
        expect(tester.takeException(), isNull);
        samples.add(sampleMemoryBytes());
      }
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    await tester.runAsync(() => client.close());
  }
  return {'metric': memoryMetric, 'after_cycle_bytes': samples};
}

Future<void> prepareWorkload() async {
  // Shared by widget tests and the isolated integration-test application.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
  await T.load(const Locale('en'));
  await initializeDateFormatting('en');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareWorkload);
  testWidgets('repeated scrolling and room switches with 551 Matrix events',
      (tester) async {
    final clock = Stopwatch()..start();
    final memory = await runTimelineWorkload(tester);
    clock.stop();
    // Host elapsed time is a diagnostic, not an FPS or startup measurement.
    debugPrint('STABILITY_METRIC ${jsonEncode({
          'scenario': 'timeline_widget_workload',
          'cycles': 10,
          'events_per_cycle': 551,
          'host_elapsed_ms': clock.elapsedMilliseconds,
          'memory': memory,
        })}');
  });
}
