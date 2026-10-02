import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/matrix/authentication/matrix_uia_request.dart';
import 'package:rooster/ui/pages/matrix/verification/matrix_verification_page.dart';

import 'package:matrix/matrix.dart' as matrix;

class MatrixKeyVerificationComponent
    implements Component<MatrixClient>, NeedsPostLoginInit {
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
        title: "Verification Request",
      );
    });

    client.matrixClient.onUiaRequest.stream.listen((event) {
      if (event.state == matrix.UiaRequestState.waitForUser) {
        AdaptiveDialog.show(
          navigator.currentContext!,
          builder: (_) => MatrixUIARequest(event, client),
          title: "Authentication Request",
        );
      }
    });
  }
}
