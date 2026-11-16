@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/ui/molecules/message_input.dart';
import 'package:rooster/ui/organisms/attachment_processor/picked_files.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';

import '../media_prepare/fakes.dart';
import '../pending_media/chat_harness.dart';

/// A picked file that fails the test when its bytes are asked for.
class _Unread extends PlatformFile {
  _Unread({required super.name, required super.size, super.path});

  @override
  Uint8List? get bytes => throw StateError('the bytes of $name were read');

  @override
  Stream<List<int>>? get readStream =>
      throw StateError('the stream of $name was read');
}

/// A picker that hands out [files] and notes each time it opens in [log].
class _Picker extends FilePicker {
  _Picker(this.files, this.log);

  final List<PlatformFile> files;
  final List<String> log;

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
  }) async {
    log.add('picker');
    return FilePickerResult(files);
  }
}

/// Lets the composer's debounced work after it took focus run, then takes
/// the chat down: run after the chat is gone, it touches a disposed state.
Future<void> settleAndClose(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await closeChat(tester);
}

void main() {
  const limit = 50 * 1000 * 1000;
  final appLimit = uploadLimitOf;
  final appPreparer = ImagePreparer.instance;
  late FakeRoom room;

  setUp(() {
    AttachmentSends.instance.clear();
    final preparer = fakePreparer(FakeEngine(width: 400, height: 300));
    ImagePreparer.instance = preparer;
    room = FakeRoom(FakeClient('a'), '!room', preparer: preparer);
  });

  tearDown(() {
    uploadLimitOf = appLimit;
    ImagePreparer.instance = appPreparer;
    AttachmentSends.instance.clear();
  });

  testWidgets(
      "the composer's attach button: the picker opens, then the server's "
      'limit is asked; a file over it is refused unread, with both sizes',
      (tester) async {
    final log = <String>[];
    uploadLimitOf = (_) async {
      log.add('limit');
      return limit;
    };
    FilePicker.platform = _Picker(
        [_Unread(name: 'big.mkv', size: 60 * 1000 * 1000, path: '/v/big')],
        log);
    await tester.pumpWidget(chatApp(room));
    await tester.pump();
    expect(log, ['limit'], reason: 'asked once as the composer opens');
    log.clear();

    await tester.tap(find.descendant(
        of: find.byType(MessageInput), matching: find.byIcon(Icons.add)));
    await tester.pump();
    await tester.pump();

    expect(log, ['picker', 'limit']);
    expect(find.text(messageFileOverUploadLimit(60 * 1000 * 1000, limit)),
        findsOneWidget);
    await settleAndClose(tester);
  });

  testWidgets(
      'a paste is checked against the limit known now; with none known yet '
      'the limit is asked again for the next paste', (tester) async {
    int? answer;
    var asks = 0;
    uploadLimitOf = (_) async {
      asks++;
      return answer;
    };
    await tester.pumpWidget(chatApp(room));
    await tester.pump();
    expect(asks, 1);
    final composer = tester.state<MessageInputState>(find.byType(MessageInput));

    answer = limit;
    expect(composer.pasteLimit(), isNull, reason: 'not known yet');
    await tester.pump();
    expect(asks, 2);
    expect(composer.pasteLimit(), limit);
    expect(asks, 2, reason: 'known: not asked again');
    await settleAndClose(tester);
  });
}
