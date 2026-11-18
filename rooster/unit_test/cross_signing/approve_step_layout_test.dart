/// matrix.org's approval step in the dialog of the server's steps, in the
/// bottom sheet a phone shows it in: whole at 280 and 320 px, in English
/// and in Portuguese (a third longer), before and after a refusal; its
/// buttons open the page and send the request again. Runs on the VM and
/// in Chrome.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:rooster/ui/pages/matrix/authentication/matrix_uia_request_view.dart';
import 'package:rooster/utils/common_strings.dart';

import '../device_verification/verify_device_layout.dart'
    show loadFontsAndLanguages, phoneScreen;
import 'approve_step_layout.dart';

void main() {
  setUpAll(loadFontsAndLanguages);
  tearDown(() => intl.Intl.defaultLocale = null);

  for (final notApprovedYet in [false, true]) {
    for (final locale in ['en', 'pt']) {
      for (final width in [280.0, 320.0]) {
        final label = '${notApprovedYet ? 'refused' : 'asked'} at '
            '${width.toInt()} px ($locale)';
        testWidgets('whole, $label', (tester) async {
          phoneScreen(tester, width);
          intl.Intl.defaultLocale = locale;
          await openApproveStep(tester, notApprovedYet: notApprovedYet);
          expectWholeTexts(
              tester, label, approveStepTexts(notApprovedYet: notApprovedYet));
          if (locale == 'pt') {
            expect(
                MatrixUIARequestView.promptRoomUiaOpenWebsite, 'Abrir o site');
          }
        });
      }
    }
  }

  testWidgets('the buttons open the page and send the request again',
      (tester) async {
    phoneScreen(tester, 320);
    var opened = 0, retried = 0;
    await openApproveStep(tester,
        onOpen: () => opened++, onRetry: () => retried++);
    await tester.tap(find.text(MatrixUIARequestView.promptRoomUiaOpenWebsite));
    expect(opened, 1);
    await tester.tap(find.text(CommonStrings.promptContinue));
    expect(retried, 1);
  });
}
