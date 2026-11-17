// The sent message of a photo whose upload runs, drawn by the timeline's
// own message widget: the stage, the count and the clock under it, and
// "Cancel send", which stops the uploads and takes the message back. Then
// the line's width, in English and Portuguese.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart' as intl;
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/client/matrix/media/async_photo_send.dart';
import 'package:rooster/client/matrix/media/interrupted_photo_uploads.dart';
import 'package:rooster/client/matrix/media/matrix_file_send.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import '../speed_log/fake_account.dart';
import 'async_fakes.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(
        Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  }
  await loader.load();
}

const _mb = 1024 * 1024;

void main() {
  testWidgets(
      'the sent message shows the stage, the count, the clock and Cancel '
      'send while the photo goes up; Cancel send aborts and takes it back',
      (tester) async {
    late MatrixClient client;
    late MatrixRoom room;
    late AsyncTransport transport;
    late TrackedMatrixAttachment attachment;
    late Future<String?> sending;
    late matrix.Event sent;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    // The client is made in the real zone: its close waits on timers.
    await tester.runAsync(() async {
      AttachmentSends.instance.clear();
      transport = AsyncTransport()
        ..holdPuts = true
        ..holdPartway = true;
      client = await fakeAccount('sent_photo_status_test', transport);
      final mx = client.getMatrixClient();
      mx.backgroundSync = false;
      await mx.oneShotSync();
      room = await plainRoom(client);
      // A photo the engine draws, over one piece of upload (64 KiB).
      final noise = img.Image(width: 400, height: 400);
      final random = math.Random(1);
      for (final pixel in noise) {
        pixel.setRgb(
            random.nextInt(256), random.nextInt(256), random.nextInt(256));
      }
      final send = AttachmentSend(roomKey: room.localId, attachment: null);
      AttachmentSends.instance.add(send);
      attachment = TrackedMatrixAttachment(
          matrix.MatrixImageFile(
              bytes: img.encodeJpg(noise, quality: 95),
              name: 'noise.jpg',
              mimeType: 'image/jpeg',
              width: 400,
              height: 400),
          send,
          thumbnailFile: matrix.MatrixImageFile(
              bytes: img.encodeJpg(img.Image(width: 40, height: 40)),
              name: 'thumbnail.jpg',
              mimeType: 'image/jpeg',
              width: 40,
              height: 40));
      sending = sendAttachment(room.matrixRoom, attachment);
      await until(() => transport.puts.length == 2);
      final photoSend =
          asyncPhotoSendOf(room.matrixRoom, attachment.send.transactionId!)!;
      sent = (await room.matrixRoom.getEventById(photoSend.eventId!))!;
    });
    expect(sent.status, matrix.EventStatus.sent);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
          body: Align(
              alignment: Alignment.topLeft,
              child: TimelineEventViewMessage(
                  room: room,
                  initialEvent: room.convertEvent(sent),
                  initialIndex: 0,
                  overrideShowSender: true,
                  previewMedia: true))),
    ));
    await tester.pump();

    final stage = find.byKey(const ValueKey('pending-file-stage'));
    expect(tester.widget<Text>(stage).data,
        PendingAttachmentStatus.labelPendingFileUploading);
    final count = tester
        .widget<Text>(find.byKey(const ValueKey('pending-file-size')))
        .data!;
    print('the sent photo\'s line: '
        '${tester.widget<Text>(stage).data} · $count · '
        '${tester.widget<Text>(find.byKey(const ValueKey('pending-file-clock'))).data}');
    expect(count, contains(' of '));
    expect(find.byKey(const ValueKey('pending-file-clock')), findsOneWidget);
    expect(find.text('Cancel send'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pending-file-cancel')));
    await tester.runAsync(() async {
      expect(await sending, isNull);
    });
    await tester.pump();
    expect(transport.abortedPuts, 2);
    expect(transport.answeredPuts, 0);
    expect(transport.log.last, 'PUT redact');
    // The line is gone with the send.
    expect(find.byKey(const ValueKey('pending-file-stage')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => client.close());
    AttachmentSends.instance.clear();
  });

  for (final locale in ['en', 'pt']) {
    testWidgets(
        'the line with Cancel send, and the message left in the room, hold '
        'whole at 280 and 320 px ($locale)', (tester) async {
      await tester.runAsync(() async {
        await _loadFont('Roboto', ['assets/font/roboto/Roboto-Regular.ttf']);
        await _loadFont('NunitoSans', [
          'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf'
        ]);
        await initializeMessages(locale);
      });
      intl.Intl.defaultLocale = locale;
      addTearDown(() => intl.Intl.defaultLocale = null);

      // The longest count: 148 MB, the original of a photo sent as it is.
      final counting = AttachmentSend(roomKey: 'a:!room', attachment: null)
        ..handedOver('counting', bytes: 148 * _mb + 300 * 1024);
      counting.upload
        ..uploadStarted(148 * _mb + 300 * 1024)
        ..uploadSent(123 * _mb + 500 * 1024);

      final cut = <String>[];
      for (final left in [false, true]) {
        for (final width in [280.0, 320.0]) {
          await tester.pumpWidget(MaterialApp(
              theme: ThemeDark.theme,
              home: Scaffold(
                  body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                          width: width,
                          child: Align(
                              alignment: Alignment.topLeft,
                              child: SentPhotoStatus(
                                  changes: counting,
                                  uploading: () => counting,
                                  leftInRoom: () => left,
                                  onCancel: () {})))))));
          // An overflowing row throws here.
          expect(tester.takeException(), isNull);
          for (final element in find
              .descendant(
                  of: find.byType(SentPhotoStatus),
                  matching: find.byType(RichText))
              .evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            if (paragraph.didExceedMaxLines) {
              cut.add('${left ? 'left' : 'counting'} @${width.toInt()}: '
                  '"${paragraph.text.toPlainText()}"');
            }
          }
          if (left) {
            expect(
                find.text(locale == 'pt'
                    ? 'A foto não subiu, e não foi possível apagar esta '
                        'mensagem'
                    : "The photo didn't upload, and this message couldn't "
                        "be deleted"),
                findsOneWidget);
          } else {
            expect(find.text(locale == 'pt' ? 'Cancelar envio' : 'Cancel send'),
                findsOneWidget);
            expect(find.byKey(const ValueKey('pending-file-clock')),
                findsOneWidget);
          }
        }
      }
      expect(cut, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }

  for (final locale in ['en', 'pt']) {
    testWidgets(
        'the failed message of a photo cut short by the app closing says so, '
        'whole at 280 and 320 px ($locale)', (tester) async {
      late MatrixClient client;
      late MatrixRoom room;
      late matrix.Event item;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
      await tester.runAsync(() async {
        await _loadFont('Roboto', ['assets/font/roboto/Roboto-Regular.ttf']);
        await _loadFont('NunitoSans', [
          'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf'
        ]);
        await initializeMessages(locale);
        client =
            await fakeAccount('interrupted_item_$locale', AsyncTransport());
        final mx = client.getMatrixClient();
        mx.backgroundSync = false;
        room = await plainRoom(client);
        await room.matrixRoom.showFailedMessage('interrupted', {
          'msgtype': 'm.notice',
          'body': 'fallback',
          interruptedPhotoKey: r'$photo',
        });
        item =
            (await mx.database.getEventById('interrupted', room.matrixRoom))!;
      });
      intl.Intl.defaultLocale = locale;
      addTearDown(() => intl.Intl.defaultLocale = null);
      expect(item.status, matrix.EventStatus.error);

      final said = locale == 'pt'
          ? 'Uma foto não terminou de subir antes de o Rooster fechar. Os '
              'outros não vão vê-la'
          : "A photo didn't finish uploading before Rooster closed. The "
              "others won't see it";
      for (final width in [280.0, 320.0]) {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: width,
                      child: TimelineEventViewMessage(
                          key: ValueKey(width),
                          room: room,
                          initialEvent: room.convertEvent(item),
                          initialIndex: 0,
                          overrideShowSender: true,
                          previewMedia: true)))),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text(said), findsOneWidget);
        expect(find.text('fallback'), findsNothing);
      }

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(() => client.close());
    });
  }
}
