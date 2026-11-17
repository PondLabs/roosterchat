@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/attachment.dart';
import 'package:rooster/ui/molecules/message_input.dart';
import 'package:rooster/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:rooster/ui/organisms/attachment_processor/picked_files.dart';
import 'package:rooster/utils/image/preparation/image_preparation.dart';
import 'package:web/web.dart' as web;

import '../media_prepare/fakes.dart';
import '../pending_media/chat_harness.dart';

/// The browser pastes [bytes] as a file named `big.png` into the page, as
/// a screenshot pasted with Ctrl+V comes.
void _paste(int bytes) {
  final files = web.DataTransfer();
  files.items.add(web.File([Uint8List(bytes).toJS].toJS, 'big.png',
      web.FilePropertyBag(type: 'image/png')));
  web.document.dispatchEvent(web.ClipboardEvent(
      'paste', web.ClipboardEventInit(clipboardData: files)));
}

/// The composer on the web: a file pasted into the page goes through the
/// server's limit before it is read.
void main() {
  testWidgets(
      "a file over the server's limit pasted into the composer is refused, "
      'and no attachment dialog opens', (tester) async {
    final appLimit = uploadLimitOf;
    final appPreparer = ImagePreparer.instance;
    addTearDown(() {
      uploadLimitOf = appLimit;
      ImagePreparer.instance = appPreparer;
      AttachmentSends.instance.clear();
    });
    final preparer = fakePreparer(FakeEngine(width: 400, height: 300));
    ImagePreparer.instance = preparer;
    uploadLimitOf = (_) async => 10;
    await tester.pumpWidget(
        chatApp(FakeRoom(FakeClient('a'), '!room', preparer: preparer)));
    await tester.pump();
    await tester.showKeyboard(find.byType(EditableText).first);
    await tester.pump();
    expect(
        tester
            .state<MessageInputState>(find.byType(MessageInput))
            .maxUploadBytes,
        10);

    _paste(20);
    // The browser reads the paste in its own turns.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump();

    expect(find.text(messageFileOverUploadLimit(20, 10)), findsOneWidget);
    expect(find.byType(AttachmentProcessor), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await closeChat(tester);
  });
}
