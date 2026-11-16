@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:matrix/fake_matrix_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/diagnostic/speed_log/host_class.dart';
import 'package:rooster/diagnostic/speed_log/speed_log.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';
import 'package:rooster/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:rooster/utils/network/speed_http_client.dart';
import 'package:rooster/utils/network/upload_progress.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../media_prepare/fakes.dart' hide NoFrames;
import '../pending_media/chat_harness.dart' show blackJpeg;
import '../pending_media/matrix_fakes.dart';
import '../speed_log/fake_account.dart';
import 'fakes.dart';

const _roomId = '!1234:fakeServer.notExisting';

/// The SDK's fake homeserver, with each `POST /upload` answered by
/// [upload].
class _Uploads extends FakeTransport {
  _Uploads(this.upload);

  final Future<http.StreamedResponse> Function(http.BaseRequest) upload;
  int count = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method == 'POST' && request.url.path.endsWith('/upload')) {
      count++;
      return upload(request);
    }
    return super.send(request);
  }
}

/// The upload loop's clock with no wait: its new attempts go at once.
class _NoWait extends matrix.SendClock {
  const _NoWait();

  @override
  Future<void> delay(Duration duration) async {}
}

/// A logged-in `matrix.Client` on [transport] under our HTTP client, whose
/// event send loop gives up after [giveUpAfter] (it decides by the real
/// clock) and whose upload loop does not wait, and a plain room it has
/// joined.
Future<(matrix.Client, matrix.Room)> _plainClient(
    String name, http.Client transport, SpeedLog log,
    {Duration giveUpAfter = const Duration(milliseconds: 100)}) async {
  final database = await matrix.MatrixSdkDatabase.init(
    name,
    database: await databaseFactoryFfi.openDatabase(':memory:',
        options: OpenDatabaseOptions(singleInstance: false)),
    sqfliteFactory: databaseFactoryFfi,
  );
  final mx = matrix.Client(name,
      database: database,
      httpClient: SpeedHttpClient(
          inner: transport,
          log: log,
          hosts: HostClassifier(
              homeserver: () => Uri.parse('https://fakeServer.notExisting'))),
      sendTimelineEventTimeout: giveUpAfter,
      sendClock: const _NoWait());
  FakeMatrixApi.client = mx;
  await mx.checkHomeserver(Uri.parse('https://fakeServer.notExisting'),
      checkWellKnown: false);
  await mx.login(
    matrix.LoginType.mLoginPassword,
    identifier: matrix.AuthenticationUserIdentifier(user: 'test'),
    password: '1234',
  );
  mx.backgroundSync = false;
  await mx.database.transaction(() => mx.handleSync(matrix.SyncUpdate(
        nextBatch: 'plain',
        rooms: matrix.RoomsUpdate(join: {
          _roomId: matrix.JoinedRoomUpdate(state: [
            matrix.MatrixEvent(
              type: matrix.EventTypes.RoomMember,
              stateKey: mx.userID,
              senderId: mx.userID!,
              eventId: '\$join',
              originServerTs: DateTime.now(),
              content: {'membership': 'join'},
            ),
          ]),
        }),
      )));
  return (mx, mx.getRoomById(_roomId)!);
}

/// A 1 MiB file sent through [room] and followed by a new [AttachmentSend].
Future<(AttachmentSend, String?, List<matrix.Event>)> _sendFile(
    matrix.Room room) async {
  final echoes = <matrix.Event>[];
  final events = room.client.onTimelineEvent.stream.listen(echoes.add);
  final send = AttachmentSend(roomKey: 'test:$_roomId', attachment: null);
  final file = matrix.MatrixFile(bytes: Uint8List(1024 * 1024), name: 'a.bin');
  final id = await sendMatrixFile(room, TrackedMatrixAttachment(file, send));
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await events.cancel();
  return (send, id, echoes);
}

Future<void> _inLocale(String locale) async {
  await initializeMessages(locale);
  intl.Intl.defaultLocale = locale;
}

/// A picker that fails the test if anything asks it for a file.
class _NoPicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) =>
      throw StateError('a file picker was opened');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appStall = UploadLimits.stall;
  tearDown(() {
    UploadLimits.stall = appStall;
    intl.Intl.defaultLocale = null;
    AttachmentSends.instance.clear();
  });

  test(
      'an upload whose connection stops taking bytes is ended by the stall '
      'limit, and the message fails when the SDK gives up', () async {
    UploadLimits.stall = const Duration(milliseconds: 300);
    final log = SpeedLog(frames: NoFrames());
    final transport = _Uploads((request) {
      final result = Completer<http.StreamedResponse>();
      late StreamSubscription<List<int>> body;
      body = request.finalize().listen((_) => body.pause());
      (request as http.Abortable).abortTrigger!.whenComplete(() {
        body.cancel();
        result.completeError(http.RequestAbortedException(request.url));
      });
      return result.future;
    });
    final (mx, room) = await _plainClient('stall_test', transport, log);

    final (send, id, echoes) = await _sendFile(room);

    expect(id, isNull);
    expect(send.stage, AttachmentSendStage.failed);
    expect(send.upload.problem, UploadProblem.other);
    expect(
        echoes.lastWhere((e) => e.eventId == send.transactionId).status.isError,
        isTrue);
    final uploads =
        log.requests.toList().where((r) => r.route.endsWith('/upload'));
    expect(uploads.map((r) => r.error).toSet(), {SpeedError.uploadStalled});
    expect(PendingAttachmentStatus.describe(send).label,
        PendingAttachmentStatus.labelPendingFileFailed);
    await mx.dispose(closeDatabase: true);
  });

  testWidgets(
      'a 524 whose body is not JSON shows "the server took too long" with '
      "the file's size, in English and in Portuguese", (tester) async {
    late AttachmentSend send;
    late matrix.Client mx;
    await tester.runAsync(() async {
      final transport = _Uploads((_) async => http.StreamedResponse(
          Stream.value(utf8.encode(
              '<html><body>Error 524: A timeout occurred</body></html>')),
          524,
          headers: {'content-type': 'text/html'}));
      final (client, room) = await _plainClient(
          'proxy_test', transport, SpeedLog(frames: NoFrames()));
      mx = client;
      (send, _, _) = await _sendFile(room);
    });
    expect(send.stage, AttachmentSendStage.failed);
    expect(send.upload.problem, UploadProblem.serverTooSlow);

    final shown = <String, String>{};
    for (final locale in ['en', 'pt']) {
      await tester.runAsync(() => _inLocale(locale));
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: PendingAttachmentStatus(send))));
      shown[locale] = tester
          .widget<Text>(find.byKey(const ValueKey('pending-file-stage')))
          .data!;
    }
    print('shown: $shown');
    expect(shown['en'], 'The server took too long with this 1 MB file');
    expect(shown['pt'], contains('1 MB'));
    expect(shown['pt'], isNot(shown['en']));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => mx.dispose(closeDatabase: true));
  });

  group('in the app', () {
    late MediaTransport transport;
    late MatrixClient client;
    late MatrixRoom room;
    final appPreparer = ImagePreparer.instance;

    Future<void> setUpAccount(String name) async {
      AttachmentSends.instance.clear();
      ImagePreparer.instance =
          fakePreparer(FakeEngine(width: 400, height: 300));
      transport = MediaTransport();
      client = await fakeAccount(name, transport);
      final mx = client.getMatrixClient();
      mx.backgroundSync = false;
      await mx.oneShotSync();
      room = await plainRoom(client);
    }

    Future<void> tearDownAccount() async {
      ImagePreparer.instance = appPreparer;
      AttachmentSends.instance.clear();
      await client.close();
    }

    test(
        'a photo with the media config cached: its uploads and one '
        'PUT /send, no config request', () async {
      await setUpAccount('config_cache_test');
      expect(await room.maxUploadBytes(), 50000000,
          reason: "the fake server's m.upload.size, now cached");
      transport.seen.clear();

      composerSend(room, attachments: [
        PendingFileAttachment(name: 'photo.jpg', data: blackJpeg(400, 300))
      ]).send();
      final send = AttachmentSends.instance.all.single;
      await until(() => send.isFinished);

      print('requests: ${transport.seen}');
      expect(send.stage, AttachmentSendStage.sent);
      final uploads =
          transport.seen.where((r) => r == 'POST /_matrix/media/v3/upload');
      final others = transport.seen.where((r) => !uploads.contains(r));
      expect(uploads, isNotEmpty);
      expect(others, hasLength(1));
      expect(others.single, startsWith('PUT '));
      expect(others.single, contains('/send/'));
      await tearDownAccount();
    });

    testWidgets(
        '"Retry" in the menu of a failed file sends it again without a file '
        'picker; "Cancel" and "Retry" only on a failed message',
        (tester) async {
      FilePicker.platform = _NoPicker();
      late AttachmentSend failedSend;
      late matrix.Event failed;
      late AttachmentSend sendingSend;
      late matrix.Event sending;
      late dynamic timeline;
      await tester.runAsync(() async {
        await setUpAccount('menu_retry_test');
        final echoes = <matrix.Event>[];
        client.getMatrixClient().onTimelineEvent.stream.listen(echoes.add);

        transport.failUploads = true;
        composerSend(room, attachments: [
          PendingFileAttachment(name: 'photo.jpg', data: blackJpeg(400, 300))
        ]).send();
        failedSend = AttachmentSends.instance.all.single;
        await until(() => failedSend.isFinished);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        failed = echoes.lastWhere((e) => e.eventId == failedSend.transactionId);

        transport
          ..failUploads = false
          ..holdUploads = Completer();
        composerSend(room, attachments: [
          PendingFileAttachment(name: 'other.jpg', data: blackJpeg(40, 30))
        ]).send();
        sendingSend = AttachmentSends.instance.all.last;
        await until(() => sendingSend.echoed);
        sending =
            echoes.lastWhere((e) => e.eventId == sendingSend.transactionId);
        timeline = await room.getTimeline();
      });
      expect(failed.status.isError, isTrue);
      expect(sending.status.isSending, isTrue);

      late BuildContext context;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ))));

      TimelineEventMenu menuOf(matrix.Event event) => TimelineEventMenu(
          timeline: timeline,
          event: room.convertEvent(event),
          context: context);
      Map<String, TimelineEventMenuEntry> entries(TimelineEventMenu menu) => {
            for (final e in [...menu.primaryActions, ...menu.secondaryActions])
              e.name: e
          };

      final onSending = menuOf(sending);
      expect(entries(onSending).keys,
          isNot(contains(onSending.promptCancelEventSend)));
      expect(entries(onSending).keys,
          isNot(contains(onSending.promptRetryEventSend)));

      final onFailed = menuOf(failed);
      expect(
          entries(onFailed).keys,
          containsAll(
              [onFailed.promptCancelEventSend, onFailed.promptRetryEventSend]));

      await tester.runAsync(() async {
        // The SDK's work runs on the real clock.
        entries(onFailed)[onFailed.promptRetryEventSend]!.action!(context);
        await until(() =>
            failedSend.stage == AttachmentSendStage.uploading &&
            failedSend.upload.waitingForServer);
        transport.holdUploads!.complete();
        await until(() =>
            failedSend.stage == AttachmentSendStage.sent &&
            sendingSend.stage == AttachmentSendStage.sent);
      });
      expect(transport.sentEvents.map((e) => e['body']),
          containsAll(['photo.jpg', 'other.jpg']));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(tearDownAccount);
    });

    testWidgets(
        '"Retry" on a file this device no longer holds keeps the failed '
        'message and says to attach it again', (tester) async {
      late matrix.Event failed;
      late dynamic timeline;
      final cancelled = <String>[];
      await tester.runAsync(() async {
        await setUpAccount('menu_restart_test');
        final mx = client.getMatrixClient();
        final echoes = <matrix.Event>[];
        mx.onTimelineEvent.stream.listen(echoes.add);
        mx.onCancelSendEvent.stream.listen(cancelled.add);
        transport.failUploads = true;
        composerSend(room, attachments: [
          PendingFileAttachment(name: 'photo.jpg', data: blackJpeg(400, 300))
        ]).send();
        final send = AttachmentSends.instance.all.single;
        await until(() => send.isFinished);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        failed = echoes.lastWhere((e) => e.eventId == send.transactionId);
        // What a restart leaves: the failed event, without its file.
        room.matrixRoom.sendingFilePlaceholders.remove(failed.eventId);
        AttachmentSends.instance.clear();
        timeline = await room.getTimeline();
        transport.seen.clear();
      });

      late BuildContext context;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ))));
      final menu = TimelineEventMenu(
          timeline: timeline,
          event: room.convertEvent(failed),
          context: context);
      await tester.runAsync(() async {
        [...menu.primaryActions, ...menu.secondaryActions]
            .firstWhere((e) => e.name == menu.promptRetryEventSend)
            .action!(context);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.text(menu.messageRetryFileNoLongerHeld), findsOneWidget);
      expect(cancelled, isEmpty, reason: 'the failed message is not hidden');
      expect(transport.seen.where((r) => r.contains('/upload')), isEmpty);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(tearDownAccount);
    });
  });
}
