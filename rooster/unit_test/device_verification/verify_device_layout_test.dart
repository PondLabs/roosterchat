/// The prompt to verify this device, in the bottom sheet a phone shows it
/// in, the Home screen's notice and the undecrypted message's line hold
/// whole at 280 and 320 px, in English and in Portuguese (a third longer).
/// Runs on the VM and in Chrome.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/ui/pages/matrix/verification/verify_this_device.dart';

import 'verify_device_layout.dart';

void main() {
  setUpAll(loadFontsAndLanguages);
  tearDown(() => intl.Intl.defaultLocale = null);

  for (final locale in ['en', 'pt']) {
    for (final width in [280.0, 320.0]) {
      testWidgets('whole at ${width.toInt()} px ($locale)', (tester) async {
        phoneScreen(tester, width);
        intl.Intl.defaultLocale = locale;
        await tester.pumpWidget(verificationTexts());
        await openPromptSheet(tester);
        expectWholeTexts(tester, '${width.toInt()} px $locale');
        if (locale == 'pt') {
          expect(find.text('Verifique este dispositivo'), findsOneWidget);
          expect(VerifyThisDevice.messageVerifyThisDeviceWhy,
              startsWith('Verifique este dispositivo'));
        }
      });
    }
  }
}
