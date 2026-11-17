@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import '../speed_log/fake_account.dart';
import 'text_send_fakes.dart';

const _clock = ValueKey("pending-message-clock");

/// The look of an own text message while it is sent (question 8 of the
/// speed work): full opacity from the first frame, a small clock only once
/// the send has taken over a second, and a failed send as it always was.
void main() {
  final appNow = PendingMessageLook.now;
  tearDown(() => PendingMessageLook.now = appNow);

  testWidgets(
      'a pending message is opaque from its first frame, its clock absent at '
      '900 ms and shown at 1,100 ms; a failed one looks as it did',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    late MatrixClient client;
    late SendTransport transport;
    final timeline = (await tester.runAsync(() async {
      transport = SendTransport();
      client = await fakeAccount('pending_look', transport);
      final mx = client.getMatrixClient();
      mx.backgroundSync = false;
      await mx.oneShotSync();
      final room = await joinedRoom(client, encrypted: false);
      return timelineWithSends(room, transport,
          failed: 'it did not go', pending: 'on its way');
    }))!;
    int indexOf(String body) => timeline.events
        .indexWhere((e) => e is TimelineEventMessage && e.body == body);
    final pending = timeline.events[indexOf('on its way')];
    expect(pending.status, TimelineEventStatus.sending);
    // The widget is drawn at the moment the message was sent; from there,
    // the test's clock.
    final sentAt = pending.originServerTs;
    final start = tester.binding.clock.now();
    PendingMessageLook.now =
        () => sentAt.add(tester.binding.clock.now().difference(start));

    Widget app(Timeline timeline, int index) => MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
          home: Scaffold(
            body: TimelineViewEntry(
                key: ValueKey(index), timeline: timeline, initialIndex: index),
          ),
        );

    /// The opacities the message's text is drawn with.
    List<double> opacities(String body) => tester
        .widgetList<Opacity>(find.ancestor(
            of: find.textContaining(body), matching: find.byType(Opacity)))
        .map((o) => o.opacity)
        .toList();

    await tester.pumpWidget(app(timeline, indexOf('on its way')));
    expect(find.textContaining('on its way'), findsOneWidget);
    expect(opacities('on its way').where((o) => o < 1), isEmpty,
        reason: 'full opacity from the first frame');
    expect(find.byKey(_clock), findsNothing);

    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(_clock), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(_clock), findsOneWidget);
    expect(opacities('on its way').where((o) => o < 1), isEmpty);
    expect(find.byIcon(Icons.error), findsNothing);

    // Once sent, the clock goes.
    await tester.runAsync(() async {
      transport.hold!.complete();
      await until(() => const [
            TimelineEventStatus.sent,
            TimelineEventStatus.synced
          ].contains(timeline.events[indexOf('on its way')].status));
    });
    tester
        .state<TimelineViewEntryState>(find.byType(TimelineViewEntry))
        .update(indexOf('on its way'));
    await tester.pump();
    expect(find.byKey(_clock), findsNothing);
    expect(opacities('on its way').where((o) => o < 1), isEmpty);

    // The failed send: half opacity and the error mark, as today; no clock.
    await tester.pumpWidget(app(timeline, indexOf('it did not go')));
    await tester.pump(const Duration(seconds: 2));
    expect(opacities('it did not go'), contains(0.5));
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.byKey(_clock), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(client.close);
  });
}
