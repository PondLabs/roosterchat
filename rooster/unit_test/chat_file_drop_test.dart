// Dragging files onto an open chat uploads them, whatever kind of file they
// are. The drop arrives from desktop_drop's platform channel, as the desktop
// sends it, reaches the chat's drop target, and the files become
// attachments.
import 'dart:io';

import 'package:rooster/ui/atoms/drag_drop_file_target.dart';
import 'package:rooster/ui/organisms/chat/dropped_files.dart';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

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
