@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import 'chat_harness.dart';

/// The question Send asks before sending a file whose metadata says, or
/// may say, where it was taken: for a file picked or pasted (its bytes in
/// memory) and for one dropped (read from its path). Every way of
/// attaching ends in the chat's `_attach`, which starts the answer, and
/// Send asks about every file it takes.
void main() {
  late FakeRoom room;
  late Directory dir;
  final appPreparer = ImagePreparer.instance;

  final gps =
      File('unit_test/fixtures/image_metadata/gps_exif.jpg').readAsBytesSync();
  // The photo cut short inside its Exif: the reader stops with an error.
  final unreadable = Uint8List.sublistView(gps, 0, 40);
  final plain = blackJpeg(400, 300);

  setUp(() {
    sent.clear();
    AttachmentSends.instance.clear();
    final preparer = fakePreparer(FakeEngine(width: 400, height: 300));
    ImagePreparer.instance = preparer;
    room = FakeRoom(FakeClient('a'), '!room', preparer: preparer);
    dir = Directory.systemTemp.createTempSync('t66_location');
  });

  tearDown(() {
    ImagePreparer.instance = appPreparer;
    AttachmentSends.instance.clear();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // The exif package leaves a file it fails to read open (its
      // readExifFromFile closes it only on success): Windows will not
      // delete it until the handle goes.
    }
  });

  test('the cut photo is one the Exif reader cannot read', () async {
    await expectLater(readExifFromBytes(unreadable), throwsA(anything));
    expect(await readExifFromBytes(plain), isEmpty);
    expect((await readExifFromBytes(gps)).keys.any((k) => k.contains('GPS')),
        isTrue);
  });

  for (final dropped in [false, true]) {
    final how = dropped ? 'dropped (read from disk)' : 'picked or pasted';

    Future<PendingFileAttachment> attach(
        WidgetTester tester, String name, Uint8List bytes) async {
      // The composer's preview cannot draw the cut photo either; that is
      // the preview's business, not this test's.
      final onError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.library == "image resource service") return;
        onError?.call(details);
      };
      addTearDown(() => FlutterError.onError = onError);

      final PendingFileAttachment file;
      if (dropped) {
        final path = '${dir.path}/$name';
        File(path).writeAsBytesSync(bytes);
        file = PendingFileAttachment(name: name, path: path);
        // A file on disk is read off the test's fake time; attaching then
        // finds its answer known.
        await tester.runAsync(() => file.locationCheck());
      } else {
        file = PendingFileAttachment(name: name, data: bytes);
      }
      chatState(tester).addAttachment(file);
      await tester.pump();
      return file;
    }

    /// Lets what runs off the test's fake time finish: a file on disk read
    /// for Send, and the location answer read off it, which Send awaits.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(seconds: 1));
      }
    }

    for (final (label, name, bytes, answer) in [
      ('with a location', 'beach.jpg', gps, LocationAnswer.found),
      (
        'whose Exif cannot be read',
        'cut.jpg',
        unreadable,
        LocationAnswer.unreadable
      ),
    ]) {
      testWidgets(
          '$how, a photo $label: Send asks; declined, nothing goes; '
          'accepted, the message goes', (tester) async {
        await tester.pumpWidget(chatApp(room));
        final file = await attach(tester, name, bytes);
        expect(file.location, answer);
        final state = chatState(tester);
        final question = answer == LocationAnswer.found
            ? state.messageChatFileHasLocation(name)
            : state.messageChatFileMetadataUnreadable(name);

        await typeAndSend(tester, 'where I was');
        await settle(tester);
        expect(find.text(question), findsOneWidget);

        await tester.tap(find.text(state.promptChatDontSendFile));
        await tester.pump(const Duration(seconds: 1));
        expect(sent, isEmpty);
        expect(AttachmentSends.instance.all, isEmpty);
        expect(composerText(tester), 'where I was');
        expect(state.attachments, [file]);

        // Asked again and accepted: the text and the file go.
        await tester.tap(find.byIcon(Icons.send));
        await tester.pump(const Duration(milliseconds: 20));
        await settle(tester);
        expect(find.text(question), findsOneWidget);
        await tester.tap(find.text(state.promptChatSendFile));
        await settle(tester);
        expect(sent.first.message, 'where I was');
        expect(composerText(tester), '');
        expect(state.attachments, isEmpty);
        expect(
            [for (final m in sent) ...m.files.map((f) => f.file.name)], [name]);

        await closeChat(tester);
      }, timeout: const Timeout(Duration(minutes: 1)));
    }

    testWidgets('$how, a photo with no Exif goes without a question',
        (tester) async {
      await tester.pumpWidget(chatApp(room));
      final file = await attach(tester, 'black.jpg', plain);
      expect(file.location, LocationAnswer.none);

      await typeAndSend(tester, 'look');
      expect(sent.first.message, 'look',
          reason: 'sent at once, with no question');
      expect(find.text(chatState(tester).promptChatDontSendFile), findsNothing);
      await settle(tester);
      expect([for (final m in sent) ...m.files.map((f) => f.file.name)],
          ['black.jpg']);

      await closeChat(tester);
    }, timeout: const Timeout(Duration(minutes: 1)));
  }
}
