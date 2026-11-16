@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_event_menu.dart';

import '../speed_log/fake_account.dart';
import '../upload_loop/loop_fakes.dart';
import 'cancel_fakes.dart';

/// A file of [fileBytes] sent through [room], followed by a new send.
(AttachmentSend, Future<String?>) _sendFile(MatrixRoom room) {
  final send = AttachmentSend(roomKey: room.localId, attachment: null);
  AttachmentSends.instance.add(send);
  final file = matrix.MatrixFile(
      bytes: Uint8List.fromList(List.filled(fileBytes, 1)), name: 'a.bin');
  return (
    send,
    sendMatrixFile(room.matrixRoom, TrackedMatrixAttachment(file, send))
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AttachmentSends.instance.clear());

  testWidgets(
      'the menu offers Cancel on a file uploading and a text waiting in the '
      "queue, not on a text whose PUT /send left; a failed one has it as "
      'before; Cancel on the queued text sends nothing', (tester) async {
    // The account's call support listens on WebRTC, which has no plugin
    // here.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (c) {
        context = c;
        return const SizedBox();
      },
    ))));

    late CancelTransport transport;
    final echoes = <matrix.Event>[];
    final offered = <String, Set<String>>{};
    late String cancel, retry;
    // All of it on the real clock. The completers are made here too: one
    // made in the test's fake zone completes only when the test pumps.
    await tester.runAsync(() async {
      transport = CancelTransport();
      final hold = Completer<void>();
      final client = await fakeAccount('menu_cancel', transport);
      final mx = client.getMatrixClient();
      mx.backgroundSync = false;
      await mx.oneShotSync();
      final room = await plainRoom(client);
      mx.onTimelineEvent.stream.listen(echoes.add);
      matrix.Event last(bool Function(matrix.Event) which) =>
          echoes.lastWhere(which);

      // A failed file.
      transport.onUpload = (_, __) async =>
          json(403, {'errcode': 'M_FORBIDDEN', 'error': 'Not now'});
      final (failedSend, failedSending) = _sendFile(room);
      expect(await failedSending, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final failed = last((e) => e.eventId == failedSend.transactionId);

      // A file uploading.
      transport
        ..onUpload = null
        ..holdUploads = true;
      final (uploadingSend, uploadingSent) = _sendFile(room);
      await until(() => transport.open == 1);
      final uploading = last((e) => e.eventId == uploadingSend.transactionId);

      // A text whose PUT /send left, and one waiting behind it.
      transport.holdNextSend = hold.future;
      final firstSent = room.sendMessage(message: 'first');
      await until(() => transport.events.length == 1);
      unawaited(room.sendMessage(message: 'second'));
      await until(() => room.matrixRoom.sendingQueue.length == 2);
      final left = last((e) => e.body == 'first');
      final queued = last((e) => e.body == 'second');
      final timeline = await room.getTimeline();

      expect(failed.status.isError, isTrue);
      for (final pending in [uploading, left, queued]) {
        expect(pending.status.isSending, isTrue);
      }
      TimelineEventMenu menuOf(matrix.Event event) => TimelineEventMenu(
          timeline: timeline,
          event: room.convertEvent(event),
          context: context);
      Map<String, TimelineEventMenuEntry> entries(TimelineEventMenu menu) => {
            for (final e in [...menu.primaryActions, ...menu.secondaryActions])
              e.name: e
          };
      cancel = menuOf(failed).promptCancelEventSend;
      retry = menuOf(failed).promptRetryEventSend;
      offered.addAll({
        'failed': entries(menuOf(failed)).keys.toSet(),
        'uploading': entries(menuOf(uploading)).keys.toSet(),
        'request left': entries(menuOf(left)).keys.toSet(),
        'queued': entries(menuOf(queued)).keys.toSet(),
      });

      entries(menuOf(queued))[cancel]!.action!(context);
      await until(() => room.matrixRoom.sendingQueue.length == 1);
      hold.complete();
      transport.releaseUploads.complete();
      await firstSent;
      await uploadingSent;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await client.close();
    });

    for (final MapEntry(:key, :value) in offered.entries) {
      print('$key: Cancel ${value.contains(cancel)}, Retry '
          '${value.contains(retry)}');
    }
    expect(offered['failed'], containsAll([cancel, retry]));
    expect(offered['uploading'], contains(cancel));
    expect(offered['uploading'], isNot(contains(retry)));
    expect(offered['request left'], isNot(contains(cancel)));
    expect(offered['request left'], isNot(contains(retry)));
    expect(offered['queued'], contains(cancel));

    final bodies = transport.events.map((e) => e.body['body']).toList();
    print('events sent: $bodies');
    expect(bodies, containsAll(['first', 'a.bin']));
    expect(bodies, isNot(contains('second')));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
