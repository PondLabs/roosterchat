import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/matrix/auth/qr_login/matrix_qr_login.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_code_data.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_error.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_protocol.dart';
import 'package:rooster/client/matrix/auth/qr_login/secure_channel.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:url_launcher/url_launcher.dart';

/// Settings > Security: sign a new device in from this one (MSC4108), with
/// the code the new device shows under its QR code. No camera is needed.
class QrLinkDeviceRow extends StatelessWidget {
  const QrLinkDeviceRow({super.key, required this.client});

  final matrix.Client client;

  static String get labelQrLinkDevice => Intl.message("Link a new device",
      name: "labelQrLinkDevice",
      desc: "Settings > Security: title of the row that signs a new device "
          "in from this one with the QR code the new device shows");

  static String get labelQrLinkDeviceExplanation => Intl.message(
      "Sign in on a new device without your password: choose \"Sign in with "
      "QR code\" there, then paste the code it shows here.",
      name: "labelQrLinkDeviceExplanation",
      desc: "Settings > Security: under \"Link a new device\"; \"Sign in with "
          "QR code\" is the login screen button of the same name");

  static String get promptQrLinkDevice => Intl.message("Link",
      name: "promptQrLinkDevice",
      desc: "Settings > Security: button that starts signing a new device in "
          "from this one");

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.label(labelQrLinkDevice),
                tiamat.Text.labelLow(labelQrLinkDeviceExplanation),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: tiamat.Button.secondary(
              key: const ValueKey('qr-link-device'),
              text: promptQrLinkDevice,
              onTap: () => AdaptiveDialog.show(context,
                  title: labelQrLinkDevice,
                  dismissible: true,
                  builder: (_) => QrLinkDeviceView(client: client)),
            ),
          ),
        ],
      );
}

class QrLinkDeviceView extends StatefulWidget {
  const QrLinkDeviceView({super.key, required this.client});

  final matrix.Client client;

  static String get labelQrLinkPasteCode => Intl.message(
      "Code from the new device",
      name: "labelQrLinkPasteCode",
      desc: "Label of the field where the code shown under the new device's "
          "QR code is pasted");

  static String get promptQrLinkPaste => Intl.message("Paste",
      name: "promptQrLinkPaste",
      desc: "Tooltip of the button that pastes the new device's code from "
          "the clipboard");

  static String get promptQrLinkConnect => Intl.message("Connect",
      name: "promptQrLinkConnect",
      desc: "Button that connects to the new device with the pasted code");

  static String get labelQrLinkCheckCode =>
      Intl.message("Type this number on the new device:",
          name: "labelQrLinkCheckCode",
          desc: "Above the 2-digit number the person types on the new device "
              "to prove no one is in between");

  static String get labelQrLinkApprove => Intl.message(
      "Approve the new device on your server's page, then come back here.",
      name: "labelQrLinkApprove",
      desc: "While the server's page that approves the new device is open "
          "in the browser");

  static String get promptQrLinkOpenPage => Intl.message("Open the page",
      name: "promptQrLinkOpenPage",
      desc: "Button that opens the server's page that approves the new "
          "device, in case it did not open by itself");

  static String get labelQrLinkSharingKeys => Intl.message(
      "Sending your keys to the new device…",
      name: "labelQrLinkSharingKeys",
      desc: "While this device sends the new one the keys to read encrypted "
          "messages");

  static String get labelQrLinkDone =>
      Intl.message("The new device is signed in and has your keys.",
          name: "labelQrLinkDone",
          desc: "After a new device was signed in from this one, with the "
              "cross-signing and backup keys");

  static String get labelQrLinkDoneWithoutKeys => Intl.message(
      "The new device is signed in. This device had no keys to send, so "
      "verify the new one to read encrypted messages there.",
      name: "labelQrLinkDoneWithoutKeys",
      desc: "After a new device was signed in from this one, when this "
          "device did not have the cross-signing keys unlocked");

  @override
  State<QrLinkDeviceView> createState() => _QrLinkDeviceViewState();
}

class _QrLinkDeviceViewState extends State<QrLinkDeviceView> {
  final code = TextEditingController();
  QrSecureChannel? channel;
  QrLoginStep? step;
  Uri? approvalPage;
  String? error;
  QrLoginSecrets? sent;
  bool busy = false;

  Future<void> connect() async {
    final QrCodeData data;
    try {
      data = QrCodeData.fromText(code.text);
      if (data.mode != QrLoginMode.login) throw const QrCodeDataException('');
    } on FormatException {
      setState(() => error = QrLoginError.notALoginCode.message);
      return;
    }
    setState(() {
      busy = true;
      error = null;
      step = QrLoginStep.connecting;
    });
    try {
      final open = channel =
          await QrSecureChannel.connect(widget.client.httpClient, data);
      final secrets = await runQrLoginExistingDevice(
        open,
        MatrixQrLoginExistingDevice(widget.client, onApprove: (page) async {
          if (mounted) setState(() => approvalPage = page);
          await launchUrl(page, mode: LaunchMode.externalApplication);
        }),
        onStep: (s) {
          if (mounted) setState(() => step = s);
        },
      );
      if (mounted) setState(() => sent = secrets);
    } on QrLoginException catch (e) {
      if (mounted) setState(() => error = e.error.message);
    } catch (_) {
      await channel?.close();
      if (mounted) setState(() => error = QrLoginError.failed.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    channel?.close();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = channel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        if (step == null || error != null) ...[
          TextField(
            key: const ValueKey('qr-link-code'),
            controller: code,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: QrLinkDeviceView.labelQrLinkPasteCode,
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste),
                tooltip: QrLinkDeviceView.promptQrLinkPaste,
                onPressed: () async {
                  final pasted = await Clipboard.getData(Clipboard.kTextPlain);
                  if (pasted?.text != null) code.text = pasted!.text!;
                },
              ),
            ),
          ),
          tiamat.Button(
            key: const ValueKey('qr-link-connect'),
            text: QrLinkDeviceView.promptQrLinkConnect,
            onTap: busy ? null : connect,
          ),
        ],
        if (error != null)
          tiamat.Text.label(error!, key: const ValueKey('qr-link-error')),
        if (error == null &&
            open != null &&
            step == QrLoginStep.confirmCheckCode) ...[
          tiamat.Text.label(QrLinkDeviceView.labelQrLinkCheckCode),
          Center(
            child: Text(open.checkCode.display,
                key: const ValueKey('qr-link-check-code'),
                style: Theme.of(context).textTheme.displayMedium),
          ),
        ],
        if (error == null && step == QrLoginStep.approve) ...[
          tiamat.Text.label(QrLinkDeviceView.labelQrLinkApprove),
          if (approvalPage != null)
            tiamat.Button.secondary(
              text: QrLinkDeviceView.promptQrLinkOpenPage,
              onTap: () => launchUrl(approvalPage!,
                  mode: LaunchMode.externalApplication),
            ),
        ],
        if (error == null && step == QrLoginStep.sharingKeys)
          tiamat.Text.labelLow(QrLinkDeviceView.labelQrLinkSharingKeys),
        if (error == null && step == QrLoginStep.done)
          tiamat.Text.label(sent?.isEmpty ?? true
              ? QrLinkDeviceView.labelQrLinkDoneWithoutKeys
              : QrLinkDeviceView.labelQrLinkDone),
        if (busy && step != QrLoginStep.approve)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
