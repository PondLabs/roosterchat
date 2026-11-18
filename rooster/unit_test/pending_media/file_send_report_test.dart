@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/diagnostic/speed_log/speed_report.dart';
import 'package:rooster/ui/organisms/chat/pending_attachments.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import '../media_prepare/fakes.dart';
import '../speed_log/fake_account.dart';
import 'chat_harness.dart' show blackJpeg;
import 'matrix_fakes.dart';

/// The speed report for one photo sent from the composer, through the real
/// `MatrixRoom` and Matrix SDK on its fake homeserver, with the chat's
/// pending slot drawing the photo: attached, Send, the photo painted, the
/// preparation with its sizes, each upload, the event, and Send to
/// confirmed.
void main() {
  final appPreparer = ImagePreparer.instance;

  testWidgets('the report shows a photo send from attach to confirmed',
      (tester) async {
    late MatrixClient client;
    late MatrixRoom room;
    late MediaTransport transport;
    // The account's WebRTC listens on this channel; no plugin in a test.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    await tester.runAsync(() async {
      AttachmentSends.instance.clear();
      SpeedLog.instance.spans.clear();
      SpeedLog.instance.requests.clear();
      // The preparation is the fake engine's (T2.2 tests the real one); the
      // photo drawn in the slot is decoded by the engine for real.
      ImagePreparer.instance = fakePreparer(
          FakeEngine(width: 1200, height: 900),
          log: SpeedLog.instance);
      transport = MediaTransport();
      client = await fakeAccount('file_send_report_test', transport);
      client.getMatrixClient().backgroundSync = false;
      await client.getMatrixClient().oneShotSync();
      room = await plainRoom(client);
    });
    addTearDown(() => ImagePreparer.instance = appPreparer);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
          body: Align(
              alignment: Alignment.bottomLeft,
              child: PendingAttachmentsView(roomKey: room.localId))),
    ));

    // Attached a moment before Send.
    final photo =
        PendingFileAttachment(name: 'holiday.jpg', data: blackJpeg(1200, 900))
          ..attachedAt =
              SpeedLog.instance.now() - const Duration(milliseconds: 1500);
    await tester.runAsync(() async {
      composerSend(room, attachments: [photo]).send();
    });
    final send = AttachmentSends.instance.all.single;
    final span = send.trace!.span;

    // Frames go on while the SDK sends: the slot draws the photo once it is
    // decoded.
    for (var i = 0; i < 400 && !span.isFinished; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(span.isFinished, isTrue);
    expect(span.outcome, SpeedOutcome.ok);

    final steps = {for (final s in span.steps) s.name: s};
    // The fake homeserver reserves no mxc: the photo goes upload first.
    expect(steps.keys, [
      SpeedStep.attached,
      SpeedStep.prepared,
      SpeedStep.uploadFirst,
      SpeedStep.previewPainted,
      SpeedStep.echo,
      SpeedStep.reserve,
      SpeedStep.upload,
      SpeedStep.request,
      SpeedStep.confirmed,
    ]);
    expect(span.steps.every((s) => s.available), isTrue,
        reason: buildSpeedReport(SpeedLog.instance));
    expect(steps[SpeedStep.attached]!.values,
        {SpeedValue.bytes: photo.data!.length});
    expect(steps[SpeedStep.attached]!.duration!.inMilliseconds,
        greaterThanOrEqualTo(1500));
    expect(steps[SpeedStep.prepared]!.values, {
      SpeedValue.bytes: photo.data!.length,
      SpeedValue.width: 1200,
      SpeedValue.height: 900,
    });
    expect(steps[SpeedStep.upload]!.values[SpeedValue.bytes],
        transport.uploadSizes.single);
    expect(steps[SpeedStep.upload]!.values[SpeedValue.status], 200);
    expect(steps[SpeedStep.request]!.values[SpeedValue.status], 200);
    // Send to confirmed spans the rest.
    final sendAt = steps[SpeedStep.attached]!.duration!;
    expect(steps[SpeedStep.confirmed]!.start, sendAt);
    expect(steps[SpeedStep.previewPainted]!.start, sendAt);

    final report = buildSpeedReport(SpeedLog.instance);
    expect(report, contains('file_send'));
    expect(report, isNot(contains('invalid_name')));
    for (final private in ['holiday', 'jpg', r'!1234', 'fakeServer', 'm.']) {
      expect(report, isNot(contains(private)), reason: private);
    }
    final out = Platform.environment['T23_EVIDENCE_DIR'];
    if (out != null) {
      File('$out/aceite7-relatorio-file-send.txt').writeAsStringSync(report);
    }
    // ignore: avoid_print
    print(report);

    await tester.runAsync(() => client.close());
    AttachmentSends.instance.clear();
  });
}
