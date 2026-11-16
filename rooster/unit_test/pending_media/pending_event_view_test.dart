@TestOn('vm')
library;

/// The room's pending file event, drawn by the timeline's own message
/// widget: the local picture, and the stage and clock under it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import '../media_prepare/fakes.dart';
import 'chat_harness.dart' show blackJpeg;
import 'matrix_fakes.dart';
import '../speed_log/fake_account.dart';

void main() {
  final appPreparer = ImagePreparer.instance;

  testWidgets(
      'the pending file event shows the local picture and its stage '
      '(uploading, then failed)', (tester) async {
    late MatrixClient client;
    late MatrixRoom room;
    late MediaTransport transport;
    late AttachmentSend send;
    final echoes = <matrix.Event>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    final photo =
        PendingFileAttachment(name: 'photo.jpg', data: blackJpeg(400, 300));
    await tester.runAsync(() async {
      AttachmentSends.instance.clear();
      ImagePreparer.instance =
          fakePreparer(FakeEngine(width: 400, height: 300));
      transport = MediaTransport()..holdUploads = Completer();
      client = await fakeAccount('pending_event_view_test', transport);
      final mx = client.getMatrixClient();
      mx.backgroundSync = false;
      await mx.oneShotSync();
      room = await plainRoom(client);
      mx.onTimelineEvent.stream.listen(echoes.add);
      composerSend(room, attachments: [photo]).send();
      send = AttachmentSends.instance.all.single;
      await until(() => send.echoed);
    });
    addTearDown(() => ImagePreparer.instance = appPreparer);

    Widget app(matrix.Event event) => MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: TimelineEventViewMessage(
                      key: ValueKey(event.status),
                      room: room,
                      initialEvent: room.convertEvent(event),
                      initialIndex: 0,
                      overrideShowSender: true,
                      previewMedia: true))),
        );

    final txid = send.transactionId!;
    final pending = echoes.lastWhere((e) => e.eventId == txid);
    await tester.pumpWidget(app(pending));
    await tester.pump();

    final stage = find.byKey(const ValueKey("pending-file-stage"));
    expect(stage, findsOneWidget);
    expect(tester.widget<Text>(stage).data,
        PendingAttachmentStatus.labelPendingFileUploading);
    expect(find.byKey(const ValueKey("pending-file-clock")), findsOneWidget);
    expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .where((i) => i.image == localPicture(photo.data!)),
        isNotEmpty);

    // The upload is refused: the same message says it failed.
    await tester.runAsync(() async {
      transport.failUploads = true;
      transport.holdUploads!.complete();
      await until(() => send.isFinished);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    final failed = echoes.lastWhere((e) => e.eventId == txid);
    expect(failed.status.isError, isTrue);
    await tester.pumpWidget(app(failed));
    await tester.pump();
    expect(find.text(PendingAttachmentStatus.labelPendingFileFailed),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    // The name colour's profile request (the fake server's 1 ms timer).
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => client.close());
    AttachmentSends.instance.clear();
  });
}
