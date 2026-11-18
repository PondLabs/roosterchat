@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/client/timeline_events/timeline_event_message.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../speed_log/fake_account.dart';
import 'text_send_fakes.dart';

/// A picture of an own message's three send states, drawn with the app's
/// fonts and theme: sending for under a second (no clock), sending for over
/// a second (the clock) and failed (as it always looked). Written as PNG to
/// `T41_EVIDENCE_DIR` (or the system's temporary folder).
void main() {
  final appNow = PendingMessageLook.now;
  tearDown(() => PendingMessageLook.now = appNow);

  Future<void> loadFont(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      loader.addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    }
    await loader.load();
  }

  testWidgets('the three states of an own message being sent', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    late MatrixClient client;
    late SendTransport transport;
    final timeline = (await tester.runAsync(() async {
      await loadFont('Roboto', ['assets/font/roboto/Roboto-Regular.ttf']);
      await loadFont('NunitoSans', [
        'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf'
      ]);
      // The icons from the test's own asset bundle (`flutter test` puts
      // Material Icons there), not from the SDK's cache, which a CI runner's
      // Flutter may not have where FLUTTER_ROOT points.
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      transport = SendTransport();
      client = await fakeAccount('pending_look_screenshot', transport);
      final mx = client.getMatrixClient();
      mx.backgroundSync = false;
      await mx.oneShotSync();
      final room = await joinedRoom(client, encrypted: false);
      // The second pending message is sent 600 ms after the first.
      return timelineWithSends(room, transport,
          failed: 'This one could not be sent.',
          pending: 'Sending for over a second: the clock shows.',
          queued: 'Sent a moment ago: no clock yet.',
          gap: const Duration(milliseconds: 600));
    }))!;
    int indexOf(String body) => timeline.events.indexWhere(
        (e) => e is TimelineEventMessage && e.body!.startsWith(body));
    final slow = indexOf('Sending for over');
    final fresh = indexOf('Sent a moment');
    final failed = indexOf('This one');
    // Drawn 1.2 s after the slow one was sent, under 0.6 s after the other.
    final drawnAt = timeline.events[slow].originServerTs
        .add(const Duration(milliseconds: 1200));
    PendingMessageLook.now = () => drawnAt;
    expect(
        drawnAt.difference(timeline.events[fresh].originServerTs) <
            PendingMessageLook.delay,
        isTrue);

    Widget entry(String caption, int index) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
              // Not translated: a caption of the test's picture.
              child: Text(caption,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ),
            TimelineViewEntry(
                timeline: timeline, initialIndex: index, singleEvent: true),
          ],
        );

    final key = GlobalKey();
    tester.view.physicalSize = const Size(640, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeDark.theme,
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              entry('Sending, 0.6 s', fresh),
              entry('Sending, 1.2 s', slow),
              entry('Failed', failed),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    const clock = ValueKey("pending-message-clock");
    expect(find.byKey(clock), findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);

    final png = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    final dir =
        Platform.environment['T41_EVIDENCE_DIR'] ?? Directory.systemTemp.path;
    final file = File('$dir/aceite5-tres-estados.png')..writeAsBytesSync(png!);
    // ignore: avoid_print
    print('wrote ${file.path} (${png.length} bytes)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() async {
      transport.hold!.complete();
      // Both sends end before the database closes.
      await until(() => [slow, fresh].every((i) => const [
            TimelineEventStatus.sent,
            TimelineEventStatus.synced
          ].contains(timeline.events[i].status)));
      await client.close();
    });
  });
}
