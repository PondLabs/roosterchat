import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/pages/matrix/verification/verify_this_device.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The line of a message that did not decrypt. On a device that still has
/// to be verified it says so, and a tap opens the prompt to verify it;
/// otherwise it is [failedText].
class UndecryptedMessageLine extends StatelessWidget {
  const UndecryptedMessageLine(
      {required this.client, required this.failedText, super.key});

  final Client client;
  final String failedText;

  static String get messageUndecryptedOnUnverifiedDevice => Intl.message(
      "This device is not verified, so this message can't be opened. Tap to verify.",
      name: "messageUndecryptedOnUnverifiedDevice",
      desc: "In the chat, in place of a message that could not be "
          "decrypted, when this device has not been verified; tapping it "
          "opens the prompt to verify this device");

  @override
  Widget build(BuildContext context) {
    final client = this.client;
    final component = client is MatrixClient
        ? client.getComponent<MatrixKeyVerificationComponent>()
        : null;
    if (client is! MatrixClient || component == null) {
      return tiamat.Text.error(failedText);
    }

    return ValueListenableBuilder<bool>(
      valueListenable: component.needed,
      builder: (context, _, __) {
        if (!MatrixKeyVerificationComponent.needsVerification(
            client.matrixClient)) {
          return tiamat.Text.error(failedText);
        }
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey("undecrypted-unverified-device"),
            behavior: HitTestBehavior.opaque,
            onTap: () => VerifyThisDevice.show(context, client),
            child: tiamat.Text.error(messageUndecryptedOnUnverifiedDevice),
          ),
        );
      },
    );
  }
}
