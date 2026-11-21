import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_key_verification_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/matrix/verification/matrix_verification_page.dart';
import 'package:rooster/ui/pages/settings/categories/account/security/matrix/cross_signing/cross_signing_page.dart';
import 'package:rooster/utils/error_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Asks to verify this device, with the two ways the app has: the recovery
/// key or security phrase (the cross-signing page), or emoji with another
/// device of the account. Closes itself once the device is verified.
class VerifyThisDevice extends StatefulWidget {
  const VerifyThisDevice({required this.client, super.key});

  final MatrixClient client;

  static String get labelVerifyThisDevice => Intl.message("Verify this device",
      name: "labelVerifyThisDevice",
      desc: "Title of the prompt that asks to verify this device (session), "
          "shown after signing in and from the notice in the Home screen");

  static String get messageVerifyThisDeviceWhy => Intl.message(
      "Verify this device to read your encrypted messages. Until then, others won't send it the keys.",
      name: "messageVerifyThisDeviceWhy",
      desc: "In the prompt to verify this device: why encrypted messages do "
          "not open on a device that has not been verified");

  static String get promptVerifyWithRecoveryKey =>
      Intl.message("Use recovery key or security phrase",
          name: "promptVerifyWithRecoveryKey",
          desc: "Button in the prompt to verify this device: verify it by "
              "typing the account's recovery key or security phrase");

  static String get promptVerifyWithOtherDevice =>
      Intl.message("Verify with another device",
          name: "promptVerifyWithOtherDevice",
          desc: "Button in the prompt to verify this device: compare emoji "
              "with another device where the account is signed in");

  static String get promptVerifyLater => Intl.message("Later",
      name: "promptVerifyLater",
      desc: "Button in the prompt to verify this device: close it for now; "
          "the notice in the Home screen opens it again");

  /// Opens the prompt for [client]'s device.
  static Future<void> show(BuildContext context, MatrixClient client) =>
      AdaptiveDialog.show(context,
          title: labelVerifyThisDevice,
          builder: (_) => VerifyThisDevice(client: client));

  @override
  State<VerifyThisDevice> createState() => _VerifyThisDeviceState();
}

class _VerifyThisDeviceState extends State<VerifyThisDevice> {
  MatrixKeyVerificationComponent? component;

  bool startingVerification = false;

  @override
  void initState() {
    super.initState();
    component = widget.client.getComponent<MatrixKeyVerificationComponent>();
    component?.needed.addListener(onNeededChanged);
  }

  @override
  void dispose() {
    component?.needed.removeListener(onNeededChanged);
    super.dispose();
  }

  /// Verified (here or on another device): this prompt's own route goes,
  /// even under the dialog that verified it.
  void onNeededChanged() {
    if (component?.needed.value != false || !mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  /// The recovery key unlocks the account's secret storage, which holds
  /// the cross-signing keys: only then can this device sign itself.
  bool get hasRecoveryKey =>
      widget.client.matrixClient.encryption?.crossSigning.enabled == true;

  @override
  Widget build(BuildContext context) {
    return VerifyThisDeviceView(
      onRecoveryKey: hasRecoveryKey ? useRecoveryKey : null,
      onOtherDevice: verifyWithOtherDevice,
      onLater: () => Navigator.of(context).pop(),
      startingVerification: startingVerification,
    );
  }

  void useRecoveryKey() {
    AdaptiveDialog.show(context,
        title: VerifyThisDevice.labelVerifyThisDevice,
        builder: (_) => MatrixCrossSigningPage(
              client: widget.client,
              mode: MatrixCrossSigningMode.verifyDevice,
              onComplete: () => component?.refresh(),
            ));
  }

  Future<void> verifyWithOtherDevice() async {
    final mx = widget.client.matrixClient;
    final ownKeys = mx.userDeviceKeys[mx.userID];
    if (ownKeys == null) return;
    setState(() => startingVerification = true);
    await ErrorUtils.tryRun(context, () async {
      final request = await ownKeys.startVerification();
      if (!mounted) return;
      AdaptiveDialog.show(context,
          builder: (_) =>
              MatrixVerificationPage(request: request, component: component),
          title: MatrixKeyVerificationComponent.labelAppVerificationRequest);
    });
    if (mounted) setState(() => startingVerification = false);
  }
}

/// What [VerifyThisDevice] shows: why, then the ways to verify. Without
/// [onRecoveryKey] (no secret storage to unlock) only the other device.
class VerifyThisDeviceView extends StatelessWidget {
  const VerifyThisDeviceView(
      {this.onRecoveryKey,
      required this.onOtherDevice,
      required this.onLater,
      this.startingVerification = false,
      super.key});

  final void Function()? onRecoveryKey;
  final void Function() onOtherDevice;
  final void Function() onLater;
  final bool startingVerification;

  @override
  Widget build(BuildContext context) {
    final onRecoveryKey = this.onRecoveryKey;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            tiamat.Text.label(VerifyThisDevice.messageVerifyThisDeviceWhy,
                key: const ValueKey("verify-device-why")),
            const SizedBox(height: 4),
            if (onRecoveryKey != null)
              tiamat.Button(
                key: const ValueKey("verify-device-recovery-key"),
                text: VerifyThisDevice.promptVerifyWithRecoveryKey,
                onTap: onRecoveryKey,
              ),
            tiamat.Button.secondary(
              key: const ValueKey("verify-device-other-device"),
              text: VerifyThisDevice.promptVerifyWithOtherDevice,
              isLoading: startingVerification,
              onTap: onOtherDevice,
            ),
            TextButton(
              key: const ValueKey("verify-device-later"),
              onPressed: onLater,
              child: tiamat.Text.labelLow(VerifyThisDevice.promptVerifyLater),
            ),
          ],
        ),
      ),
    );
  }
}
