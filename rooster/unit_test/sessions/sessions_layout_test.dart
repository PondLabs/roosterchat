@TestOn('vm')
library;

/// The sessions settings on a phone at 280 and 320 px, in English and in
/// Portuguese (a third longer): on matrix.org after coming back from its
/// account page, and on a server that lets no app sign sessions out.
/// Every text whole. Pictures go to SESSIONS_EVIDENCE_DIR (or the
/// system's temporary folder).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/matrix_security_tab.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../device_verification/verify_device_layout.dart'
    show loadFontsAndLanguages;
import 'sessions_server.dart';

void main() {
  setUpAll(() async {
    await loadFontsAndLanguages();
    // The sessions' "Last Seen" dates, as the app does at startup.
    await initializeDateFormatting();
  });
  setUp(() => UrlLauncherPlatform.instance = FakeBrowser());
  tearDown(() => intl.Intl.defaultLocale = null);

  for (final kind in [SessionsKind.accountService, SessionsKind.neither]) {
    for (final locale in ['en', 'pt']) {
      for (final width in [280.0, 320.0]) {
        final label = '${kind.name} ${width.toInt()} px $locale';
        testWidgets('whole at $label', (tester) async {
          final server = SessionsServer(kind);
          final client = await signIn(tester, server);
          // Signing in reset the preferences: a phone again.
          await tester.runAsync(() => preferences.layoutOverride.set('mobile'));
          intl.Intl.defaultLocale = locale;
          final key = GlobalKey();
          await openSessions(tester, client,
              width: width, height: 1700, boundary: key);
          final texts = <String>[];
          if (kind == SessionsKind.accountService) {
            await press(tester, endInactiveButton);
            server.endOnAccountPage('OLDPHONE');
            await leaveAndComeBack(tester);
            await settle(
                tester, () => find.text('OLDPHONE').evaluate().isEmpty);
            texts.addAll([
              MatrixSecurityTab.messageSettingsSessionsOnAccountPage,
              MatrixSecurityTab.messageSettingsSessionsSignedOut(1),
            ]);
            expect(endInactiveButton, findsOneWidget);
          } else {
            texts.add(MatrixSecurityTab.messageSettingsSessionsCannotSignOut);
          }
          _expectWholeTexts(tester, label, texts);
          await _picture(tester, key, '${kind.name}-${width.toInt()}-$locale');
        });
      }
    }
  }
}

/// Every text on screen: none cut, none wider than its box, and [texts]
/// shown.
void _expectWholeTexts(WidgetTester tester, String label, List<String> texts) {
  expect(tester.takeException(), isNull, reason: '$label: overflow');
  for (final p in tester.renderObjectList<RenderParagraph>(
      find.byType(RichText, skipOffstage: false))) {
    final text = p.text.toPlainText();
    expect(p.didExceedMaxLines, isFalse, reason: '$label: "$text" is cut');
    expect(p.size.width <= p.constraints.maxWidth + 0.5, isTrue,
        reason: '$label: "$text" is wider than its box');
  }
  for (final text in texts) {
    expect(find.text(text), findsOneWidget, reason: '$label: "$text"');
  }
}

Future<void> _picture(WidgetTester tester, GlobalKey key, String name) async {
  final png = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final dir = Platform.environment['SESSIONS_EVIDENCE_DIR'] ??
      Directory.systemTemp.path;
  final file = File('$dir/sessions-$name.png')..writeAsBytesSync(png!);
  // ignore: avoid_print
  print('wrote ${file.path} (${png.length} bytes)');
}
