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

const _mb = 1024 * 1024;

/// Every state the line shows for a 48 MB file (148 MB while counting, the
/// longest count).
Map<String, AttachmentSend> _states() {
  AttachmentSend file(String txid, {int bytes = 48 * _mb + 300 * 1024}) =>
      AttachmentSend(roomKey: 'a:!room', attachment: null)
        ..handedOver(txid, bytes: bytes);

  final tooSlow = file('slow');
  tooSlow.upload
    ..uploadStarted(1)
    ..uploadFailed(SpeedError.uploadNoAnswer);
  tooSlow.failed();

  final failed = file('failed');
  failed.upload
    ..uploadStarted(1)
    ..uploadFailed(SpeedError.uploadStalled);
  failed.failed();

  final waiting = file('waiting');
  waiting.upload
    ..uploadStarted(10)
    ..uploadSent(10)
    ..uploadHandedOver();

  final counting = file('counting', bytes: 148 * _mb + 300 * 1024);
  counting.upload
    ..uploadStarted(148 * _mb + 300 * 1024)
    ..uploadSent(123 * _mb + 500 * 1024);

  final retrying = file('retrying', bytes: 148 * _mb + 300 * 1024);
  retrying.upload
    ..uploadStarted(10)
    ..uploadFailed(SpeedError.http)
    ..uploadStarted(148 * _mb + 300 * 1024)
    ..uploadSent(123 * _mb + 500 * 1024);

  final encrypting = file('encrypting')..encryptingFile();

  return {
    'server too slow': tooSlow,
    'failed': failed,
    'waiting for the server': waiting,
    'counting': counting,
    'retrying': retrying,
    'encrypting': encrypting,
    'sending the message': file('sending')..uploaded(),
    'preparing': AttachmentSend(roomKey: 'a:!room', attachment: null),
  };
}

void main() {
  for (final locale in ['en', 'pt']) {
    testWidgets(
        'the status line holds every state whole at 280, 320 and 360 px '
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

      final cut = <String>[];
      for (final MapEntry(key: name, value: send) in _states().entries) {
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
              cut.add('$name @${width.toInt()}: '
                  '"${paragraph.text.toPlainText()}"');
            }
          }
          final stage = tester
              .widget<Text>(find.byKey(const ValueKey('pending-file-stage')));
          if (name == 'server too slow') {
            expect(
                stage.data, contains(locale == 'pt' ? '48,29 MB' : '48.29 MB'));
          }
        }
      }
      expect(cut, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
