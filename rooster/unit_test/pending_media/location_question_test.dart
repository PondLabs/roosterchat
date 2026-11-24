@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/utils/image/metadata/remove_image_metadata.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../image_metadata/remove_image_metadata_test.dart' show riffChunk;
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
  // A readable Exif with no location: the orientation alone.
  final orientationOnly = removeMetadataByRewrite(
          File('unit_test/fixtures/image_metadata/orientation_6.jpg')
              .readAsBytesSync())!
      .bytes!;

  // The fixture's segments: SOI, APP0 JFIF, APP1 Exif, then COM, APP2 and
  // the DQT tables before the frame.
  final segments = _jpegSegments(gps);
  final soi = Uint8List.sublistView(gps, 0, 2);
  final (_, app0Start, app0End) = segments.firstWhere((s) => s.$1 == 0xE0);
  final (_, app1Start, app1End) = segments.firstWhere((s) => s.$1 == 0xE1);
  final app0 = Uint8List.sublistView(gps, app0Start, app0End);
  final app1 = Uint8List.sublistView(gps, app1Start, app1End);
  final afterApp1 = Uint8List.sublistView(gps, app1End);
  final afterDqt = segments.lastWhere((s) => s.$1 == 0xDB).$3;
  final tiff = Uint8List.sublistView(app1, 10);
  Uint8List cat(List<List<int>> parts) =>
      Uint8List.fromList([for (final p in parts) ...p]);
  // A segment of [length] (its length field), [head] first, zeros after.
  Uint8List segment(int marker, int length, [List<int> head = const []]) =>
      Uint8List(2 + length)
        ..[0] = 0xFF
        ..[1] = marker
        ..[2] = length >> 8
        ..[3] = length & 0xFF
        ..setRange(4, 4 + head.length, head);
  final icc = [...'ICC_PROFILE'.codeUnits, 0];

  // Files that hold the fixture's whole Exif, GPS and all, where the Exif
  // reader gives up without an error and finds nothing (the review's
  // probes): the block is looked into, and they get the location question.
  // The photo cut inside its IFD0, before the GPS pointer, gets the
  // unreadable one.
  final hidden = <(String, Uint8List, LocationAnswer)>[
    (
      'an APP2 of 5,000 bytes before the Exif',
      cat([soi, segment(0xE2, 5000, icc), app1, afterApp1]),
      LocationAnswer.found
    ),
    (
      'JFIF, an APP2 of 5,000 bytes, then the Exif',
      cat([soi, app0, segment(0xE2, 5000, icc), app1, afterApp1]),
      LocationAnswer.found
    ),
    (
      'a comment of 5,000 bytes before the Exif',
      cat([soi, segment(0xFE, 5000), app1, afterApp1]),
      LocationAnswer.found
    ),
    (
      'the Exif after the quantisation tables',
      cat([
        soi,
        app0,
        Uint8List.sublistView(gps, app1End, afterDqt),
        app1,
        Uint8List.sublistView(gps, afterDqt),
      ]),
      LocationAnswer.found
    ),
    (
      'a WebP whose odd-sized image chunk comes before the EXIF',
      _webpWith(tiff),
      LocationAnswer.found
    ),
    (
      'the photo cut inside its IFD0',
      Uint8List.sublistView(gps, 0, 100),
      LocationAnswer.unreadable
    ),
  ];

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
    expect(
        (await readExifFromBytes(orientationOnly)).keys, ['Image Orientation']);
  });

  test(
      'the hidden files hold the GPS block, and the Exif reader finds no '
      'location in them', () async {
    for (final (label, bytes, _) in hidden) {
      final read = await readExifFromBytes(bytes);
      if (bytes.length == 100) {
        // Cut before its GPS pointer: the camera tags, nothing more.
        expect(read.keys.any((k) => k.contains('GPS')), isFalse);
        continue;
      }
      expect(read, isEmpty, reason: label);
      if (bytes[0] == 0xFF) {
        // Another reader still finds the location.
        expect(img.decodeJpgExif(bytes)!.gpsIfd.keys, isNotEmpty,
            reason: label);
      }
    }
  });

  test('every hidden file gets its answer, from memory and disk', () async {
    for (final (i, (label, bytes, answer)) in hidden.indexed) {
      expect(
          await PendingFileAttachment(name: 'a', data: bytes).locationCheck(),
          answer,
          reason: label);
      final path = '${dir.path}/hidden$i';
      File(path).writeAsBytesSync(bytes);
      expect(await PendingFileAttachment(name: 'a', path: path).locationCheck(),
          answer,
          reason: '$label, on disk');
    }
    for (final bytes in [plain, orientationOnly]) {
      expect(
          await PendingFileAttachment(name: 'a', data: bytes).locationCheck(),
          LocationAnswer.none);
    }
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
      for (final (i, (hiddenLabel, bytes, answer)) in hidden.indexed)
        (
          'with its Exif hidden from the reader ($hiddenLabel)',
          'hidden$i.jpg',
          bytes,
          answer
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

    for (final (label, bytes) in [
      ('no Exif', plain),
      ('a readable Exif without a location', orientationOnly),
    ]) {
      testWidgets('$how, a photo with $label goes without a question',
          (tester) async {
        await tester.pumpWidget(chatApp(room));
        final file = await attach(tester, 'black.jpg', bytes);
        expect(file.location, LocationAnswer.none);

        await typeAndSend(tester, 'look');
        expect(composerText(tester), '',
            reason: 'sent at once, with no question');
        expect(
            find.text(chatState(tester).promptChatDontSendFile), findsNothing);
        await settle(tester);
        // The text is the photo's caption (Matrix v1.10): one message.
        expect(sent.single.message, 'look');
        expect([for (final m in sent) ...m.files.map((f) => f.file.name)],
            ['black.jpg']);

        await closeChat(tester);
      }, timeout: const Timeout(Duration(minutes: 1)));
    }
  }
}

/// The segments of a JPEG up to its first scan, as (marker, start, end).
List<(int, int, int)> _jpegSegments(Uint8List b) {
  final out = <(int, int, int)>[];
  var pos = 2;
  while (b[pos + 1] != 0xDA) {
    final end = pos + 2 + (b[pos + 2] << 8 | b[pos + 3]);
    out.add((b[pos + 1], pos, end));
    pos = end;
  }
  return out;
}

/// A still WebP: VP8X (EXIF flag), the animated fixture's first image
/// chunk (a VP8L of 439 bytes, odd, so its padding byte follows) and an
/// EXIF chunk holding [tiff].
Uint8List _webpWith(Uint8List tiff) {
  final webp = File('unit_test/fixtures/image_metadata/animated_exif.webp')
      .readAsBytesSync();
  final data = ByteData.sublistView(webp);
  var pos = 12;
  while (String.fromCharCodes(webp, pos, pos + 4) != 'ANMF') {
    final size = data.getUint32(pos + 4, Endian.little);
    pos += 8 + size + (size & 1);
  }
  // The frame's width and height minus one, 24 bits each, as VP8X has them.
  final frame = Uint8List.sublistView(webp, pos + 8 + 6, pos + 8 + 12);
  final image = pos + 8 + 16;
  final imageSize = data.getUint32(image + 4, Endian.little);
  // Built while the tests are declared, so checked without expect.
  if (String.fromCharCodes(webp, image, image + 4) != 'VP8L' ||
      imageSize.isEven) {
    throw StateError('the first frame is not an odd-sized VP8L');
  }
  final vp8x = Uint8List(10)
    ..[0] = 0x08 // EXIF
    ..setRange(4, 10, frame);
  final body = <int>[
    ...'WEBP'.codeUnits,
    ...riffChunk('VP8X', vp8x),
    ...riffChunk('VP8L', webp.sublist(image + 8, image + 8 + imageSize)),
    ...riffChunk('EXIF', tiff),
  ];
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ...(ByteData(4)..setUint32(0, body.length, Endian.little))
        .buffer
        .asUint8List(),
    ...body,
  ]);
}
