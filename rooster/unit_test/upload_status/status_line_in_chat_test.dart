@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/diagnostic/speed_log/speed_names.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/organisms/chat/pending_attachments.dart';
import 'package:tiamat/config/style/theme_dark.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(
        Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  }
  await loader.load();
}

const _mb = 1024 * 1024;

/// Every failure the line says in a sentence, for a 48 MB file.
Map<String, AttachmentSend> _failures() {
  AttachmentSend file(String txid) =>
      AttachmentSend(roomKey: 'a:!room', attachment: null)
        ..handedOver(txid, bytes: 48 * _mb + 300 * 1024);

  final tooSlow = file('slow');
  tooSlow.upload
    ..uploadStarted(1)
    ..uploadFailed(SpeedError.uploadNoAnswer);
  final stalled = file('stalled');
  stalled.upload
    ..uploadStarted(1)
    ..uploadFailed(SpeedError.uploadStalled);
  final changed = file('changed')..upload.fileChanged();
  final asked = file('asked')
    ..upload.serverAskedToWait(DateTime(2026, 11, 17, 12, 34));
  return {
    'server too slow': tooSlow..failed(),
    'failed': stalled..failed(),
    'file changed': changed..failed(),
    'server asked to wait': asked..failed(),
  };
}

/// The failure of a file in the chat's own slot, which has 16 px of
/// margin on each side and the dismiss button beside the clock: the whole
/// sentence fits a chat 280 and 320 px wide, in English and in Portuguese
/// (a third longer), with an hour on the clock.
void main() {
  final appClock = AttachmentSend.clock;
  tearDown(() => AttachmentSend.clock = appClock);

  for (final locale in ['en', 'pt']) {
    testWidgets(
        'every failure sentence is whole in the chat at 280 and 320 px '
        '($locale)', (tester) async {
      await tester.runAsync(() async {
        await _loadFont('Roboto', ['assets/font/roboto/Roboto-Regular.ttf']);
        await _loadFont('NunitoSans', [
          'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf'
        ]);
        await initializeMessages(locale);
      });
      intl.Intl.defaultLocale = locale;
      addTearDown(() => intl.Intl.defaultLocale = null);
      var now = Duration.zero;
      AttachmentSend.clock = () => now;

      final cut = <String>[];
      final shown = <String>[];
      final failures = _failures();
      // The longest clock the line shows: an hour and more.
      now = const Duration(hours: 1, minutes: 2, seconds: 3);
      for (final MapEntry(key: name, value: send) in failures.entries) {
        for (final width in [280.0, 320.0]) {
          await tester.pumpWidget(MaterialApp(
              theme: ThemeDark.theme,
              home: Scaffold(
                  body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                          width: width, child: PendingAttachmentTile(send))))));
          expect(tester.takeException(), isNull, reason: '$name @$width');
          expect(find.byIcon(Icons.close_rounded), findsOneWidget,
              reason: 'the dismiss button is there');
          final stage = tester.renderObject<RenderParagraph>(find.descendant(
              of: find.byKey(const ValueKey('pending-file-stage')),
              matching: find.byType(RichText)));
          shown.add('$name @${width.toInt()}: '
              '${stage.text.toPlainText()} (${stage.size.width.round()} px)');
          final texts = find.descendant(
              of: find.byType(PendingAttachmentTile),
              matching: find.byType(RichText));
          for (final element in texts.evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            if (paragraph.didExceedMaxLines) {
              cut.add('$name @${width.toInt()}: '
                  '"${paragraph.text.toPlainText()}"');
            }
          }
        }
      }
      print('shown:\n${shown.join('\n')}');
      expect(cut, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
