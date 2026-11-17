@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/components/threads/thread_component.dart';
import 'package:rooster/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/matrix_timeline.dart';
import 'package:rooster/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:rooster/client/timeline.dart';
import 'package:rooster/diagnostic/speed_log/file_send_trace.dart';
import 'package:rooster/ui/organisms/chat/composer_send.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import '../speed_log/fake_account.dart';
import 'chat_harness.dart' show blackJpeg;
import 'matrix_fakes.dart';

/// A file sent in a thread: its pending event joins the thread's list once
/// uploaded (when it gets its thread relation), where it goes, without
/// taking another event's place, and the chat's own slot gives way to it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MediaTransport transport;
  late MatrixClient client;
  late matrix.Client mx;
  late MatrixRoom room;
  late MatrixTimeline main;
  final appPreparer = ImagePreparer.instance;
  const root = r'$root';

  setUp(() async {
    AttachmentSends.instance.clear();
    ImagePreparer.instance = fakePreparer(FakeEngine(width: 400, height: 300));
    transport = MediaTransport();
    client = await fakeAccount('thread_file_test', transport);
    mx = client.getMatrixClient();
    mx.backgroundSync = false;
    await mx.oneShotSync();
    room = await plainRoom(client);
    main = await room.getTimeline() as MatrixTimeline;
  });

  tearDown(() async {
    ImagePreparer.instance = appPreparer;
    AttachmentSends.instance.clear();
    await client.close();
  });

  MatrixThreadTimeline threadOf(String rootId) => MatrixThreadTimeline(
      client: client,
      room: room,
      threadRootId: rootId,
      mainRoomTimeline: main,
      component: client.getComponent<ThreadsComponent>()!);

  /// Someone's message in the thread of [root], from the server.
  Future<void> messageInThread(String id) async {
    await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
          nextBatch: id,
          rooms: matrix.RoomsUpdate(join: {
            room.identifier: matrix.JoinedRoomUpdate(
                timeline: matrix.TimelineUpdate(events: [
              matrix.MatrixEvent(
                type: matrix.EventTypes.Message,
                senderId: '@bob:fakeServer.notExisting',
                eventId: id,
                originServerTs: DateTime.now(),
                content: {
                  'msgtype': 'm.text',
                  'body': 'in the thread',
                  'm.relates_to': {
                    'rel_type': 'm.thread',
                    'event_id': root,
                  },
                },
              ),
            ])),
          }),
        )));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  /// A photo sent from the chat of the thread of [rootId].
  AttachmentSend sendPhoto(String rootId) {
    ComposerSend(
      chatRoom: room,
      room: room,
      threads: client.getComponent<ThreadsComponent>(),
      threadId: rootId,
      message: '',
      attachments: [
        PendingFileAttachment(name: 'photo.jpg', data: blackJpeg(400, 300))
      ],
      interactionType: null,
      interactingEvent: null,
      sendPressed: FileSendTrace.now(),
    ).send();
    return AttachmentSends.instance.all.single;
  }

  bool isOf(AttachmentSend send, dynamic event) =>
      event.eventId == send.transactionId ||
      (event is MatrixTimelineEvent &&
          event.event.transactionId == send.transactionId);

  /// How many times the thread's chat shows [send]'s file: its own slot
  /// and the thread's list.
  int shown(MatrixThreadTimeline thread, AttachmentSend send, String rootId) =>
      AttachmentSends.instance
          .inComposerOf(room.localId, rootId)
          .where((s) => s == send)
          .length +
      thread.events.where((e) => isOf(send, e)).length;

  test(
      'a file joining an empty thread is listed, without a RangeError; in a '
      'thread with messages it goes first and the newest one stays', () async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      await messageInThread(r'$inthread');
      final thread = threadOf(root);
      final empty = threadOf(r'$quiet');
      addTearDown(thread.close);
      addTearDown(empty.close);
      await messageInThread(r'$newest');
      expect([for (final e in thread.events) e.eventId], [r'$newest']);

      transport.holdSends = Completer();
      final inEmpty = sendPhoto(r'$quiet');
      await until(() => transport.sentEvents.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(empty.events.where((e) => isOf(inEmpty, e)), hasLength(1));
      transport.holdSends!.complete();
      await until(() => inEmpty.isFinished);
      AttachmentSends.instance.clear();

      transport.holdSends = Completer();
      final inThread = sendPhoto(root);
      await until(() => transport.sentEvents.length == 2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final listed = [for (final e in thread.events) e.eventId];
      print('the thread with messages, its file uploaded: $listed');
      expect(listed, [inThread.transactionId, r'$newest']);
      transport.holdSends!.complete();
      await until(() => inThread.isFinished);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(thread.events.where((e) => isOf(inThread, e)), hasLength(1));
      expect(thread.events.last.eventId, r'$newest');
    }, (error, _) => errors.add(error));
    expect(errors, isEmpty);
  });

  for (final refused in [false, true]) {
    test(
        'in a thread with messages the file shows once, in the slot or in the '
        'list, while it uploads, after the upload and once '
        '${refused ? 'refused' : 'sent'}', () async {
      await messageInThread(r'$inthread');
      final thread = threadOf(root);
      addTearDown(thread.close);
      final counts = <String, int>{};

      transport.holdUploads = Completer();
      transport.holdSends = Completer();
      transport.refuseSends = refused;
      final send = sendPhoto(root);
      await until(() => transport.uploadSizes.isNotEmpty);
      counts['uploading'] = shown(thread, send, root);

      transport.holdUploads!.complete();
      await until(() => transport.sentEvents.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      counts['uploaded, PUT /send held'] = shown(thread, send, root);
      final slots = AttachmentSends.instance.inComposerOf(room.localId, root);

      transport.holdSends!.complete();
      await until(() => send.isFinished);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      counts[refused ? 'refused' : 'sent'] = shown(thread, send, root);
      print('times the file is shown: $counts; slot after the upload '
          '${slots.length}; stage ${send.stage}');
      expect(counts.values, everyElement(1));
      expect(slots, isEmpty, reason: 'the list shows it, the slot gives way');
      expect(send.stage,
          refused ? AttachmentSendStage.failed : AttachmentSendStage.sent);
      if (refused) {
        final failed = thread.events.singleWhere((e) => isOf(send, e));
        expect(failed.status, TimelineEventStatus.error,
            reason: 'the failure stays in sight');
        // Closed, the thread gives the file back to the chat's slot.
        await thread.close();
        expect(
            AttachmentSends.instance.inComposerOf(room.localId, root), [send]);
      }
    });
  }
}
