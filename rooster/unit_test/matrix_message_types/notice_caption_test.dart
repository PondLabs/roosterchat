// Criterion 3: a file sent with text carries it as its caption (Matrix
// v1.10, MSC2530: `body` is the caption, `filename` the file's own name),
// and the timeline draws the two apart; without text, a file is sent and
// drawn as before. An `m.notice` is marked apart from an `m.text`.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/client/matrix/matrix_attachment.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/client/matrix/matrix_room.dart';
import 'package:rooster/ui/molecules/timeline_events/events/timeline_event_view_notice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../pending_media/matrix_fakes.dart';
import 'harness.dart';

PendingFileAttachment eggs([String name = 'eggs.bin']) => PendingFileAttachment(
    name: name,
    data: Uint8List.fromList(List.filled(64, 7)),
    mimeType: 'application/octet-stream');

void main() {
  late MatrixClient client;
  late MatrixRoom room;
  late MediaTransport transport;

  setUpAll(() async {
    sqfliteFfiInit();
    (client, room, transport) = await messageTypesRoom('notice_caption_test');
  });

  tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

  setUp(() => transport.sentEvents.clear());

  /// Lets every send in flight reach the fake server.
  Future<void> settle(int events) async {
    await until(() => transport.sentEvents.length >= events);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  group('sending a caption', () {
    test('one file with text: body is the caption, filename the name',
        () async {
      composerSend(room, message: 'Fresh eggs', attachments: [eggs()]).send();
      await settle(1);

      expect(transport.sentEvents, hasLength(1));
      final content = transport.sentEvents.single;
      expect(content['msgtype'], matrix.MessageTypes.File);
      expect(content['body'], 'Fresh eggs');
      expect(content['filename'], 'eggs.bin');
      expect(content['url'], startsWith('mxc://'));
      expect(content.containsKey('format'), isFalse);
    });

    test('a formatted caption carries its formatted body', () async {
      composerSend(room, message: '**Fresh** eggs', attachments: [eggs()])
          .send();
      await settle(1);

      final content = transport.sentEvents.single;
      expect(content['body'], '**Fresh** eggs');
      expect(content['filename'], 'eggs.bin');
      expect(content['format'], 'org.matrix.custom.html');
      expect(content['formatted_body'], contains('<strong>Fresh</strong>'));
    });

    test('without text, the file is sent as before', () async {
      composerSend(room, attachments: [eggs()]).send();
      await settle(1);

      final content = transport.sentEvents.single;
      expect(content['body'], 'eggs.bin');
      expect(content['filename'], 'eggs.bin');
    });

    test('text with two files goes on its own, as before', () async {
      composerSend(room,
          message: 'Two baskets',
          attachments: [eggs('a.bin'), eggs('b.bin')]).send();
      await settle(3);

      expect(transport.sentEvents, hasLength(3));
      final text = transport.sentEvents
          .where((c) => c['msgtype'] == matrix.MessageTypes.Text);
      expect(text.single['body'], 'Two baskets');
      final files = transport.sentEvents
          .where((c) => c['msgtype'] == matrix.MessageTypes.File)
          .toList();
      expect(files.map((c) => c['body']), unorderedEquals(['a.bin', 'b.bin']));
      expect(files.every((c) => c['body'] == c['filename']), isTrue);
    });

    test('a reply keeps its text apart, with the relation', () async {
      final repliedTo = convertMessage(room, {
        'msgtype': 'm.text',
        'body': 'Any eggs?',
      });
      final file = await room.processAttachment(eggs());
      await room.sendMessage(
          message: 'Here', inReplyTo: repliedTo, processedAttachments: [file!]);
      await settle(2);

      final text = transport.sentEvents
          .singleWhere((c) => c['msgtype'] == matrix.MessageTypes.Text);
      expect(text['body'], contains('Here'));
      expect(text['m.relates_to'], isNotNull);
      final sentFile = transport.sentEvents
          .singleWhere((c) => c['msgtype'] == matrix.MessageTypes.File);
      expect(sentFile['body'], 'eggs.bin');
    });

    test('the room sends a caption with its own file content', () async {
      final file = MatrixProcessedAttachment(matrix.MatrixFile(
          bytes: Uint8List.fromList([1, 2, 3]),
          name: 'nest.bin',
          mimeType: 'application/octet-stream'));
      await room.sendMessage(message: 'The nest', processedAttachments: [file]);
      await settle(1);

      final content = transport.sentEvents.single;
      expect(content['body'], 'The nest');
      expect(content['filename'], 'nest.bin');
      expect(content['m.mentions'], isA<Map>());
    });
  });

  group('drawing a caption', () {
    Map<String, Object?> file(String body, {String? filename}) => {
          'msgtype': 'm.file',
          'body': body,
          if (filename != null) 'filename': filename,
          'url': 'mxc://fakeServer.notExisting/eggs',
          'info': {'mimetype': 'application/pdf', 'size': 1024},
        };

    testWidgets('name and caption are drawn apart', (tester) async {
      await useLocale('en');
      await pumpMessage(tester, room, file('Fresh eggs', filename: 'eggs.pdf'));

      expect(find.text('Fresh eggs', findRichText: true), findsOneWidget);
      expect(find.text('eggs.pdf', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without a caption, only the name', (tester) async {
      await useLocale('en');
      await pumpMessage(tester, room, file('eggs.pdf', filename: 'eggs.pdf'));
      expect(find.text('eggs.pdf', findRichText: true), findsOneWidget);
    });

    testWidgets('a legacy file without filename: body is its name',
        (tester) async {
      await useLocale('en');
      await pumpMessage(tester, room, file('old.pdf'));
      expect(find.text('old.pdf', findRichText: true), findsOneWidget);
    });

    testWidgets('a formatted caption is sanitized', (tester) async {
      await useLocale('en');
      await pumpMessage(tester, room, {
        ...file('Fresh eggs', filename: 'eggs.pdf'),
        'format': 'org.matrix.custom.html',
        'formatted_body': '<b>Fresh</b> eggs<script>alert(1)</script>'
            '<iframe src="https://evil.example"></iframe>'
            '<span style="background:url(https://evil.example/x)">!</span>',
      });

      expect(find.textContaining('Fresh', findRichText: true), findsWidgets);
      expect(find.textContaining('alert', findRichText: true), findsNothing);
      expect(find.textContaining('evil', findRichText: true), findsNothing);
      expect(find.text('eggs.pdf', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a caption with mentions but no formatted body still shows',
        (tester) async {
      await useLocale('en');
      await pumpMessage(tester, room, {
        ...file('Look, Alice', filename: 'eggs.pdf'),
        'm.mentions': {
          'user_ids': [alice],
        },
      });
      expect(
          find.textContaining('Look, Alice', findRichText: true), findsWidgets);
      expect(find.text('eggs.pdf', findRichText: true), findsOneWidget);
    });

    testWidgets('a caption on audio is drawn under the player', (tester) async {
      await useLocale('en');
      await pumpMessage(tester, room, {
        'msgtype': 'm.audio',
        'body': 'Morning song',
        'filename': 'rooster.ogg',
        'url': 'mxc://fakeServer.notExisting/song',
        'info': {'mimetype': 'audio/ogg', 'duration': 3000},
      });
      expect(find.text('Morning song', findRichText: true), findsOneWidget);
      expect(find.text('rooster.ogg', findRichText: true), findsOneWidget);
    });
  });

  group('m.notice', () {
    for (final (locale, label) in [
      ('en', 'Automated notice'),
      ('pt', 'Aviso automático'),
    ]) {
      testWidgets('a notice is marked ($locale)', (tester) async {
        await useLocale(locale);
        await pumpMessage(
            tester, room, {'msgtype': 'm.notice', 'body': 'Build 42 passed'});

        expect(find.byKey(TimelineEventViewNotice.markerKey), findsOneWidget);
        expect(find.text(label), findsOneWidget);
        expect(
            find.text('Build 42 passed', findRichText: true), findsOneWidget);
      });
    }

    testWidgets('a text message is not marked', (tester) async {
      await useLocale('en');
      await pumpMessage(
          tester, room, {'msgtype': 'm.text', 'body': 'Build 42 passed'});

      expect(find.byKey(TimelineEventViewNotice.markerKey), findsNothing);
      expect(find.byType(TimelineEventViewNotice), findsNothing);
      expect(find.text('Build 42 passed', findRichText: true), findsOneWidget);
    });

    test('only m.notice is a notice', () {
      expect(
          convertMessage(room, {'msgtype': 'm.notice', 'body': 'x'}).isNotice,
          isTrue);
      expect(convertMessage(room, {'msgtype': 'm.text', 'body': 'x'}).isNotice,
          isFalse);
    });
  });
}
