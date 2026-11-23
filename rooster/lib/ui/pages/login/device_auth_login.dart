import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:rooster/client/matrix/auth/matrix_device_auth_flow.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:url_launcher/url_launcher.dart';

/// The login screen's "Sign in from another device" button, shown only when
/// the server's `auth_metadata` has a `device_authorization_endpoint`.
class DeviceAuthLoginButton extends StatelessWidget {
  const DeviceAuthLoginButton({
    super.key,
    required this.authMetadata,
    required this.onPressed,
  });

  final matrix.GetAuthMetadataResponse? authMetadata;
  final VoidCallback? onPressed;

  static String get promptLoginDeviceAuth =>
      Intl.message("Sign in from another device",
          name: "promptLoginDeviceAuth",
          desc: "Button on the login screen that shows a code to approve on a "
              "phone or computer already able to sign in to the server");

  @override
  Widget build(BuildContext context) {
    if (!MatrixDeviceAuthFlow.isSupportedBy(authMetadata)) {
      return const SizedBox.shrink();
    }
    return tiamat.Button.secondary(
      key: const ValueKey('device-auth-login'),
      text: promptLoginDeviceAuth,
      onTap: onPressed,
    );
  }
}

/// The code to approve, its link and QR code, while the device grant polls.
class DeviceAuthPanel extends StatefulWidget {
  const DeviceAuthPanel({super.key, required this.flow});

  final MatrixDeviceAuthFlow flow;

  static String get labelDeviceAuthWaitingForCode =>
      Intl.message("Getting a code from your server…",
          name: "labelDeviceAuthWaitingForCode",
          desc: "On the login screen, while the server is asked for a code to "
              "sign in from another device");

  static String get labelDeviceAuthInstructions => Intl.message(
      "On a phone or computer, scan the QR code or open the link, then check "
      "that it shows this code:",
      name: "labelDeviceAuthInstructions",
      desc: "On the login screen, above the sign-in code, explaining how to "
          "approve the sign-in on another device");

  static String get labelDeviceAuthWaitingForApproval => Intl.message(
      "Waiting for you to approve on the other device…",
      name: "labelDeviceAuthWaitingForApproval",
      desc: "On the login screen, under the sign-in code, while Rooster waits "
          "for the sign-in to be approved on another device");

  static String get promptDeviceAuthCopyCode => Intl.message("Copy code",
      name: "promptDeviceAuthCopyCode",
      desc: "Button that copies the sign-in code to the clipboard");

  static String get promptDeviceAuthCopyLink => Intl.message("Copy link",
      name: "promptDeviceAuthCopyLink",
      desc: "Button that copies the link of the page where the sign-in is "
          "approved to the clipboard");

  static String get promptDeviceAuthOpenLink => Intl.message("Open link",
      name: "promptDeviceAuthOpenLink",
      desc: "Button that opens the page where the sign-in is approved in the "
          "browser of this device");

  @override
  State<DeviceAuthPanel> createState() => _DeviceAuthPanelState();
}

class _DeviceAuthPanelState extends State<DeviceAuthPanel> {
  String? _copied;

  Future<void> _copy(String what, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _copied = what);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DeviceAuthorizationPrompt?>(
      valueListenable: widget.flow.prompt,
      builder: (context, prompt, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          tiamat.Text.labelEmphasised(
              DeviceAuthLoginButton.promptLoginDeviceAuth),
          if (prompt == null) ...[
            tiamat.Text.labelLow(DeviceAuthPanel.labelDeviceAuthWaitingForCode),
            const Center(child: CircularProgressIndicator()),
          ] else
            ..._prompt(prompt),
          tiamat.Button.secondary(
            key: const ValueKey('device-auth-cancel'),
            text: CommonStrings.promptCancel,
            onTap: widget.flow.cancel,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  List<Widget> _prompt(DeviceAuthorizationPrompt prompt) {
    final link = prompt.link.toString();
    return [
      tiamat.Text.labelLow(DeviceAuthPanel.labelDeviceAuthInstructions),
      Center(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(8),
          child: SizedBox.square(
            dimension: 160,
            child: PrettyQrView(
              qrImage: QrImage(QrCode.fromData(
                data: link,
                errorCorrectLevel: QrErrorCorrectLevel.M,
              )),
              decoration: const PrettyQrDecoration(
                shape: PrettyQrSquaresSymbol(color: Colors.black),
                background: Colors.white,
              ),
            ),
          ),
        ),
      ),
      SelectableText(
        prompt.userCode,
        key: const ValueKey('device-auth-user-code'),
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .headlineMedium
            ?.copyWith(fontFamily: 'monospace', letterSpacing: 2),
      ),
      SelectableText(link, textAlign: TextAlign.center),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          tiamat.Button.secondary(
            key: const ValueKey('device-auth-copy-code'),
            text: _copied == 'code'
                ? CommonStrings.promptCopyComplete
                : DeviceAuthPanel.promptDeviceAuthCopyCode,
            onTap: () => _copy('code', prompt.userCode),
          ),
          tiamat.Button.secondary(
            key: const ValueKey('device-auth-copy-link'),
            text: _copied == 'link'
                ? CommonStrings.promptCopyComplete
                : DeviceAuthPanel.promptDeviceAuthCopyLink,
            onTap: () => _copy('link', link),
          ),
          tiamat.Button.secondary(
            text: DeviceAuthPanel.promptDeviceAuthOpenLink,
            onTap: () =>
                launchUrl(prompt.link, mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      tiamat.Text.labelLow(DeviceAuthPanel.labelDeviceAuthWaitingForApproval),
    ];
  }
}
