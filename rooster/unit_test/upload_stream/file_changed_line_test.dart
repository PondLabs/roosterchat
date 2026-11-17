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
import 'package:rooster/ui/molecules/timeline_events/events/pending_attachment_status.dart';
import 'package:tiamat/config/style/theme_dark.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(
        Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  }
  await loader.load();
}

/// A 148 MB file sent from disk that changed on the way.
AttachmentSend _changed() {
  final send = AttachmentSend(roomKey: 'a:!room', attachment: null)
    ..handedOver('changed', bytes: 148 * 1024 * 1024 + 300 * 1024);
  send.upload
    ..uploadStarted(10)
    ..uploadFailed(SpeedError.other)
    ..fileChanged();
  send.failed();
  return send;
}

void main() {
  for (final locale in ['en', 'pt']) {
    testWidgets(
        'the line of a file that changed on disk holds whole at 280, 320 '
        'and 360 px ($locale)', (tester) async {
      await tester.runAsync(() async {
        await _loadFont('Roboto', ['assets/font/roboto/Roboto-Regular.ttf']);
        await _loadFont('NunitoSans', [
          'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf'
        ]);
        await initializeMessages(locale);
      });
      intl.Intl.defaultLocale = locale;
      addTearDown(() => intl.Intl.defaultLocale = null);

      final send = _changed();
      final cut = <String>[];
      for (final width in [280.0, 320.0, 360.0]) {
        await tester.pumpWidget(MaterialApp(
            theme: ThemeDark.theme,
            home: Scaffold(
                body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                        width: width,
                        child: Align(
                            alignment: Alignment.topLeft,
                            child: PendingAttachmentStatus(send,
                                onDismiss: () {})))))));
        // An overflowing row throws here.
        expect(tester.takeException(), isNull);
        final texts = find.descendant(
            of: find.byType(PendingAttachmentStatus),
            matching: find.byType(RichText));
        for (final element in texts.evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          if (paragraph.didExceedMaxLines) {
            cut.add('@${width.toInt()}: "${paragraph.text.toPlainText()}"');
          }
        }
        final stage = tester
            .widget<Text>(find.byKey(const ValueKey('pending-file-stage')));
        expect(
            stage.data,
            locale == 'pt'
                ? 'O arquivo foi alterado ou apagado'
                : 'The file was changed or deleted');
      }
      print('$locale: cut $cut');
      expect(cut, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
