import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/client/attachment.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/organisms/chat/pending_attachments.dart';
import 'package:tiamat/config/style/theme_dark.dart';

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

void main() {
  tearDown(() {
    intl.Intl.defaultLocale = null;
    AttachmentSends.instance.clear();
  });

  for (final locale in ['en', 'pt']) {
    testWidgets(
        '"The server is busy. You can retry at ..." is whole on a 320 px '
        'chat, with its time ($locale)', (tester) async {
      await tester.runAsync(() async {
        await _loadFont('Roboto', 'assets/font/roboto/Roboto-Regular.ttf');
        await _loadFont('NunitoSans',
            'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf');
        await initializeMessages(locale);
      });
      intl.Intl.defaultLocale = locale;
      final appClock = AttachmentSend.clock;
      var now = Duration.zero;
      AttachmentSend.clock = () => now;
      addTearDown(() => AttachmentSend.clock = appClock);

      for (final megabytes in [48, 1023]) {
        AttachmentSends.instance.clear();
        now = Duration.zero;
        final send = AttachmentSend(roomKey: 'a:!room', attachment: null)
          ..handedOver('x', bytes: megabytes * 1024 * 1024);
        send.upload
          ..uploadStarted(1)
          ..uploadAnswered(429, matrixError: true)
          ..serverAskedToWait(DateTime(2026, 11, 16, 22, 48));
        // The longest clock the line shows below an hour.
        now = const Duration(minutes: 59, seconds: 59);
        send.failed();
        await tester.pumpWidget(MaterialApp(
            theme: ThemeDark.theme,
            locale: Locale(locale),
            supportedLocales: const [Locale('en'), Locale('pt')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
                body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                        width: 320, child: PendingAttachmentTile(send))))));
        expect(tester.takeException(), isNull);
        final line = tester.renderObject<RenderParagraph>(
            find.byKey(const ValueKey('pending-file-stage')));
        final text = line.text.toPlainText();
        print('320 px $locale, $megabytes MB: "$text" '
            '(${line.constraints.maxWidth.toStringAsFixed(0)} px), cut '
            '${line.didExceedMaxLines}');
        expect(line.didExceedMaxLines, isFalse);
        expect(text, contains(RegExp(r'10:48|22:48')));
        expect(find.byKey(const ValueKey('pending-file-size')), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
