import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/alert.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/ui/molecules/alert_view.dart';
import 'package:rooster/ui/molecules/timeline_events/events/undecrypted_message_line.dart';
import 'package:rooster/ui/pages/matrix/verification/verify_this_device.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The app's fonts, from its own asset bundle (on the VM and in Chrome).
Future<void> loadAppFonts() async {
  for (final (family, path) in [
    ('Roboto', 'assets/font/roboto/Roboto-Regular.ttf'),
    (
      'NunitoSans',
      'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf'
    ),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(path))).load();
  }
}

/// Loads the app's fonts and both languages, on the VM. In Chrome the
/// asset and message loading never ends inside `flutter test` (12 minutes,
/// then the timeout), so there the texts are English, in the test font,
/// whose square glyphs are wider than the app's.
Future<void> loadFontsAndLanguages() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) return;
  await loadAppFonts();
  await initializeMessages('en');
  await initializeMessages('pt');
}

/// The prompt (both ways), the Home screen's notice and the undecrypted
/// message's line, [width] wide, as a phone shows them.
Widget verificationTexts(double width, {Key? boundary}) {
  final alert = Alert(AlertType.warning,
      titleGetter: () => MatrixKeyVerificationComponent.labelDeviceNotVerified,
      messageGetter: () =>
          MatrixKeyVerificationComponent.messageDeviceNotVerified);
  return MaterialApp(
    theme: ThemeDark.theme,
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      // Scrolls, as the dialog that shows the prompt does.
      body: SingleChildScrollView(
          child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: boundary,
          child: Material(
            color: ThemeDark.theme.colorScheme.surfaceContainerLow,
            child: SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tiamat.Text.largeTitle(
                      VerifyThisDevice.labelVerifyThisDevice),
                  VerifyThisDeviceView(
                      onRecoveryKey: () {},
                      onOtherDevice: () {},
                      onLater: () {}),
                  const Divider(),
                  AlertView(alert),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: tiamat.Text.error(UndecryptedMessageLine
                        .messageUndecryptedOnUnverifiedDevice),
                  ),
                ],
              ),
            ),
          ),
        ),
      )),
    ),
  );
}

/// Every text on screen: none cut, none wider than its box.
void expectWholeTexts(WidgetTester tester, String label) {
  expect(tester.takeException(), isNull, reason: '$label: overflow');
  final paragraphs =
      tester.renderObjectList<RenderParagraph>(find.byType(RichText));
  expect(paragraphs, isNotEmpty);
  for (final p in paragraphs) {
    final text = p.text.toPlainText();
    expect(p.didExceedMaxLines, isFalse, reason: '$label: "$text" is cut');
    expect(p.size.width <= p.constraints.maxWidth + 0.5, isTrue,
        reason: '$label: "$text" is wider than its box');
  }
  for (final text in [
    VerifyThisDevice.messageVerifyThisDeviceWhy,
    VerifyThisDevice.promptVerifyWithRecoveryKey,
    VerifyThisDevice.promptVerifyWithOtherDevice,
    VerifyThisDevice.promptVerifyLater,
    MatrixKeyVerificationComponent.messageDeviceNotVerified,
    UndecryptedMessageLine.messageUndecryptedOnUnverifiedDevice,
  ]) {
    expect(find.text(text), findsOneWidget, reason: '$label: "$text"');
  }
}
