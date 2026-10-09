import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/matrix/authentication/matrix_uia_request.dart';
import 'package:rooster/ui/pages/matrix/verification/matrix_verification_page.dart';

import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixKeyVerificationComponent
    implements Component<MatrixClient>, NeedsPostLoginInit {
  static String get labelAppVerificationRequest =>
      Intl.message("Verification Request",
          name: "labelAppVerificationRequest",
          desc: "Title of the dialog that opens when another session or "
              "person asks to verify this session");

  static String get labelAppAuthenticationRequest =>
      Intl.message("Authentication Request",
          name: "labelAppAuthenticationRequest",
          desc: "Title of the dialog that opens when the server asks you to "
              "confirm who you are (your password) before an action");

  @override
  MatrixClient client;

  MatrixKeyVerificationComponent(this.client);

  @override
  void postLoginInit() {
    Log.i("Registering key verification listeners");
    client.matrixClient.onKeyVerificationRequest.stream.listen((event) {
      AdaptiveDialog.show(
        navigator.currentContext!,
        builder: (_) => MatrixVerificationPage(request: event),
        title: labelAppVerificationRequest,
      );
    });

    client.matrixClient.onUiaRequest.stream.listen((event) {
      if (event.state == matrix.UiaRequestState.waitForUser) {
        AdaptiveDialog.show(
          navigator.currentContext!,
          builder: (_) => MatrixUIARequest(event, client),
          title: labelAppAuthenticationRequest,
        );
      }
    });
  }
}
