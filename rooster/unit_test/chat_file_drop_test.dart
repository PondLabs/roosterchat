// Dragging files onto an open chat uploads them, whatever kind of file they
// are. The drop arrives from desktop_drop's platform channel, as the desktop
// sends it, reaches the chat's drop target, and the files become
// attachments.
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/atoms/drag_drop_file_target.dart';
import 'package:rooster/ui/organisms/attachment_processor/picked_files.dart';
import 'package:rooster/ui/organisms/chat/dropped_files.dart';
import 'package:rooster/utils/event_bus.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import 'media_prepare/fakes.dart';
import 'pending_media/chat_harness.dart';

/// A dropped file of [size] bytes that fails the test when any of its
/// bytes is read: only its length may be asked.
class _Unread extends XFile {
  _Unread(super.path, this.size);

  final int size;
  final List<String> reads = [];

  @override
  Future<int> length() async => size;

  @override
  Future<Uint8List> readAsBytes() {
    reads.add('readAsBytes');
    throw StateError('the bytes of $name were read');
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    reads.add('openRead');
    throw StateError('the bytes of $name were read');
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) {
    reads.add('readAsString');
    throw StateError('the bytes of $name were read');
  }
}

/// What desktop_drop's native side sends on a drop at [at].
Future<void> drop(WidgetTester tester, List<String> paths, Offset at) async {
  Future<void> send(String method, Object arguments) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'desktop_drop',
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall(method, arguments)),
          (_) {});
  await send('entered', [at.dx, at.dy]);
  await send('updated', [at.dx, at.dy]);
  await send('performOperation', paths);
  await tester.pump();
}

void main() {
  late Directory dir;
  late List<String> files;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('chat_drop');
    files = [
      for (final name in ['notes.txt', 'archive.zip', 'tool.exe', 'NOEXT'])
        (File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3, 4])).path,
    ];
  });

  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('files dropped on the chat reach it, every kind of file',
      (tester) async {
    final received = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: DragDropFileTarget(
          onDropComplete: (d) =>
              received.add([for (final f in d.files) f.path]),
        ),
      ),
    ));

    await drop(tester, files, const Offset(200, 200));

    expect(received, [files]);
  });

  testWidgets('a drop on a spot another target takes is not the chat\'s',
      (tester) async {
    final received = <DropDoneDetails>[];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: DragDropFileTarget(
          ignoreAt: (p) => p.dx < 100,
          onDropComplete: received.add,
        ),
      ),
    ));

    await drop(tester, files, const Offset(50, 200));

    expect(received, isEmpty);
  });

  testWidgets(
      'with no text channel open, a drop says to select one, for a moment',
      (tester) async {
    final received = <DropDoneDetails>[];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: DragDropFileTarget(
          canReceive: () => false,
          onDropComplete: received.add,
        ),
      ),
    ));

    await drop(tester, files, const Offset(200, 200));
    // What desktop_drop sends once the drag has gone.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'desktop_drop',
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('exited', null)),
        (_) {});
    await tester.pump(const Duration(seconds: 1));

    expect(received, isEmpty);
    expect(
        find.text('Select a text channel first to send files'), findsOneWidget);
    final message = find.ancestor(
        of: find.text('Select a text channel first to send files'),
        matching: find.byType(AnimatedOpacity));
    expect(tester.widget<AnimatedOpacity>(message).opacity, 1);

    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<AnimatedOpacity>(message).opacity, 0);
  });

  test('every kind of file becomes an attachment, with its type', () async {
    final attachments = await attachmentsFromDroppedFiles(files.map(XFile.new));

    expect([for (final a in attachments) a.name],
        ['notes.txt', 'archive.zip', 'tool.exe', 'NOEXT']);
    expect([for (final a in attachments) a.data], everyElement(isNotNull));
    expect(attachments[0].mimeType, 'text/plain');
    expect(attachments[1].mimeType, 'application/zip');
  });

  test('a folder in the drop is left out, not the end of the drop', () async {
    final folder = Directory('${dir.path}/folder')..createSync();
    final skipped = <String>[];

    final attachments = await attachmentsFromDroppedFiles(
        [XFile(folder.path), ...files.map(XFile.new)],
        onSkipped: (name, _) => skipped.add(name));

    expect(skipped, ['folder']);
    expect(attachments, hasLength(4));
  });

  test('a big file is read from its path on desktop, held in the browser',
      () async {
    final big = XFile.fromData(Uint8List(droppedFileInMemoryLimit + 1),
        name: 'big.bin', path: '/somewhere/big.bin');

    final [desktop] = await attachmentsFromDroppedFiles([big]);
    final [browser] = await attachmentsFromDroppedFiles([big], inBrowser: true);

    expect(desktop.data, isNull);
    expect(desktop.path, '/somewhere/big.bin');
    expect(browser.data, hasLength(droppedFileInMemoryLimit + 1));
    expect(browser.path, isNull);
  });

  test(
      "a file over the server's limit is refused by its length, unread; "
      'one within it is attached', () async {
    final big = _Unread('/somewhere/big.mkv', 60 * 1000 * 1000);
    final refused = <(int, int)>[];

    final attachments = await attachmentsFromDroppedFiles(
        [big, XFile(files.first)],
        maxBytes: 50 * 1000 * 1000,
        onRefused: (bytes, limit) => refused.add((bytes, limit)));

    expect(big.reads, isEmpty, reason: 'not one byte read');
    expect(refused, [(60 * 1000 * 1000, 50 * 1000 * 1000)]);
    expect([for (final a in attachments) a.path], [files.first]);
  });

  for (final locale in ['en', 'pt']) {
    testWidgets(
        "a file over the server's limit dropped on the chat is refused "
        'unread, with the sentence a picked one gets ($locale)',
        (tester) async {
      await tester.runAsync(() => initializeMessages(locale));
      intl.Intl.defaultLocale = locale;
      final appLimit = uploadLimitOf;
      final appPreparer = ImagePreparer.instance;
      addTearDown(() {
        intl.Intl.defaultLocale = null;
        uploadLimitOf = appLimit;
        ImagePreparer.instance = appPreparer;
      });
      final preparer = fakePreparer(FakeEngine(width: 400, height: 300));
      ImagePreparer.instance = preparer;
      uploadLimitOf = (_) async => 50 * 1000 * 1000;
      final room = FakeRoom(FakeClient('a'), '!room', preparer: preparer);
      await tester.pumpWidget(chatApp(room));
      await tester.pump();
      final big = _Unread('/somewhere/big.mkv', 60 * 1000 * 1000);

      EventBus.onFileDropped.add(DropDoneDetails(
          files: [big],
          localPosition: const Offset(400, 300),
          globalPosition: const Offset(400, 300)));
      await tester.pump();
      await tester.pump();

      final sentence =
          messageFileOverUploadLimit(60 * 1000 * 1000, 50 * 1000 * 1000);
      expect(sentence,
          contains(locale == 'pt' ? 'deste servidor' : "server's limit"));
      expect(find.text(sentence), findsOneWidget);
      expect(big.reads, isEmpty);
      expect(chatState(tester).attachments, isEmpty);
      await tester.pump(const Duration(seconds: 5));
      await closeChat(tester);
    });
  }

  group('a thread open beside the chat', () {
    const chat = Rect.fromLTWH(300, 0, 500, 800);
    const thread = Rect.fromLTWH(800, 0, 400, 800);

    test('a drop on the chat goes to the chat alone', () {
      const at = Offset(400, 400);
      expect(
          chatTakesDrop(mine: chat, isThread: false, others: [thread], at: at),
          isTrue);
      expect(
          chatTakesDrop(mine: thread, isThread: true, others: [chat], at: at),
          isFalse);
    });

    test('a drop on the thread goes to the thread alone', () {
      const at = Offset(900, 400);
      expect(
          chatTakesDrop(mine: chat, isThread: false, others: [thread], at: at),
          isFalse);
      expect(
          chatTakesDrop(mine: thread, isThread: true, others: [chat], at: at),
          isTrue);
    });

    test('a drop anywhere else goes to the room\'s chat', () {
      const at = Offset(100, 400);
      expect(
          chatTakesDrop(mine: chat, isThread: false, others: [thread], at: at),
          isTrue);
      expect(
          chatTakesDrop(mine: thread, isThread: true, others: [chat], at: at),
          isFalse);
    });
  });
}
