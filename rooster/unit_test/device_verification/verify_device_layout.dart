import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/client/alert.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/generated/intl/messages_all.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/molecules/alert_view.dart';
import 'package:rooster/ui/molecules/timeline_events/events/undecrypted_message_line.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/matrix/verification/verify_this_device.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The app's fonts, from its own asset bundle.
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

/// Both languages, the phone layout (as on Android or a phone's browser;
/// on Windows the width alone never gives it) and, on the VM, the app's
/// fonts. In Chrome loading a font asset never ends inside `flutter test`
/// (12 minutes, then the timeout), so there the texts are in the test
/// font, whose square glyphs are wider than the app's.
Future<void> loadFontsAndLanguages() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) await loadAppFonts();
  await initializeMessages('en');
  await initializeMessages('pt');
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
  await preferences.layoutOverride.set('mobile');
}

/// A phone [width] wide: the Home screen's notice and the undecrypted
/// message's line, as wide as the screen.
Widget verificationTexts({Key? boundary}) {
  final alert = Alert(AlertType.warning,
      titleGetter: () => MatrixKeyVerificationComponent.labelDeviceNotVerified,
      messageGetter: () =>
          MatrixKeyVerificationComponent.messageDeviceNotVerified);
  return RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      navigatorKey: navigator,
      theme: ThemeDark.theme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
  );
}

/// Opens the prompt as [VerifyThisDevice.show] does, which on a phone is
/// the bottom sheet, with its own padding and title.
Future<void> openPromptSheet(WidgetTester tester) async {
  AdaptiveDialog.show(navigator.currentContext!,
      title: VerifyThisDevice.labelVerifyThisDevice,
      builder: (_) => VerifyThisDeviceView(
          onRecoveryKey: () {}, onOtherDevice: () {}, onLater: () {}));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget,
      reason: 'a phone shows the prompt as a bottom sheet');
}

/// A phone screen [width] wide.
void phoneScreen(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
    VerifyThisDevice.labelVerifyThisDevice,
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
