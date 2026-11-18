import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show UiaRequestState;
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/matrix/authentication/matrix_uia_request_view.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/config/style/theme_dark.dart';

/// The dialog of the server's steps on matrix.org's approval step, as the
/// app opens it (on a phone, the bottom sheet), before the person
/// approved or, when [notApprovedYet], once the server still refused.
Future<void> openApproveStep(WidgetTester tester,
    {bool notApprovedYet = false,
    Key? boundary,
    void Function()? onOpen,
    void Function()? onRetry}) async {
  await tester.pumpWidget(RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      navigatorKey: navigator,
      theme: ThemeDark.theme,
      debugShowCheckedModeBanner: false,
      home: const Scaffold(body: SizedBox.expand()),
    ),
  ));
  AdaptiveDialog.show(navigator.currentContext!,
      title: MatrixKeyVerificationComponent.labelAppAuthenticationRequest,
      builder: (_) => MatrixUIARequestView(UiaRequestState.waitForUser,
          nextSteps: const {'m.oauth', 'org.matrix.cross_signing_reset'},
          accountPage: Uri.parse('https://account.matrix.org/'),
          notApprovedYet: notApprovedYet,
          onOpenAccountPage: onOpen,
          onRetry: onRetry));
  await tester.pumpAndSettle();
}

/// The texts of the step in that state.
List<String> approveStepTexts({required bool notApprovedYet}) => [
      MatrixKeyVerificationComponent.labelAppAuthenticationRequest,
      notApprovedYet
          ? MatrixUIARequestView.messageRoomUiaNotApprovedYet
          : MatrixUIARequestView.messageRoomUiaApproveOnWebsite,
      MatrixUIARequestView.promptRoomUiaOpenWebsite,
      notApprovedYet ? CommonStrings.promptRetry : CommonStrings.promptContinue,
    ];

/// Every text on screen: none cut, none wider than its box, and [texts]
/// shown.
void expectWholeTexts(WidgetTester tester, String label, List<String> texts) {
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
  for (final text in texts) {
    expect(find.text(text), findsOneWidget, reason: '$label: "$text"');
  }
}
