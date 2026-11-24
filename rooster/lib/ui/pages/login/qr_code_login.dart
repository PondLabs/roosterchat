import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:rooster/client/matrix/auth/matrix_device_auth_flow.dart';
import 'package:rooster/client/matrix/auth/qr_login/matrix_qr_login.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_error.dart';
import 'package:rooster/client/matrix/auth/qr_login/qr_login_protocol.dart';
import 'package:rooster/client/matrix/auth/qr_login/secure_channel.dart';
import 'package:rooster/ui/pages/login/device_auth_login.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The login screen's "Sign in with QR code" button. QR code login signs
/// in through the device authorization grant, so it shows only when the
/// server's `auth_metadata` has one.
class QrLoginButton extends StatelessWidget {
  const QrLoginButton(
      {super.key, required this.authMetadata, required this.onPressed});

  final matrix.GetAuthMetadataResponse? authMetadata;
  final VoidCallback? onPressed;

  static String get promptLoginWithQrCode =>
      Intl.message("Sign in with QR code",
          name: "promptLoginWithQrCode",
          desc: "Button on the login screen that shows a QR code to scan "
              "with a device where the person is already signed in");

  @override
  Widget build(BuildContext context) {
    if (!MatrixDeviceAuthFlow.isSupportedBy(authMetadata)) {
      return const SizedBox.shrink();
    }
    return tiamat.Button.secondary(
      key: const ValueKey('qr-login'),
      text: promptLoginWithQrCode,
      onTap: onPressed,
    );
  }
}

/// Everything that tells the person where the new device is, from the QR
/// code to the keys arriving.
class QrLoginStrings {
  static String get labelQrLoginWaitingForScan => Intl.message(
      "On a device where you are signed in, open Settings, Account, Security, "
      "Link a new device, and scan this QR code or paste the code under it.",
      name: "labelQrLoginWaitingForScan",
      desc: "On the login screen, above the QR code that a signed-in device "
          "scans to sign this device in");

  static String get labelQrLoginEnterCheckCode =>
      Intl.message("Type the 2-digit number your other device shows.",
          name: "labelQrLoginEnterCheckCode",
          desc: "On the login screen, after the other device read the QR code: "
              "the person types the number it shows, which proves no one is in "
              "between");

  static String get labelQrLoginCheckCodeField => Intl.message("Number",
      name: "labelQrLoginCheckCodeField",
      desc: "Label of the field for the 2-digit number shown on the other "
          "device");

  static String get labelQrLoginWaitingForApproval =>
      Intl.message("Approve the sign-in on your other device.",
          name: "labelQrLoginWaitingForApproval",
          desc: "On the login screen, while the signed-in device opens the "
              "server's page to approve this device");

  static String get labelQrLoginSigningIn => Intl.message("Signing in…",
      name: "labelQrLoginSigningIn",
      desc: "On the login screen, once the other device approved and "
          "this device gets its session");

  static String get labelQrLoginSharingKeys => Intl.message(
      "Getting your keys from your other device…",
      name: "labelQrLoginSharingKeys",
      desc: "On the login screen, while the signed-in device sends the keys "
          "that let this device read encrypted messages");

  static String get errorQrLoginServerUnsupported => Intl.message(
      "Your server does not support signing in with a QR code.",
      name: "errorQrLoginServerUnsupported",
      desc: "On the login screen, after the QR code button, when the server "
          "has no rendezvous for QR code login");

  static String get promptQrLoginTryAgain => Intl.message("Try again",
      name: "promptQrLoginTryAgain",
      desc: "Button that starts signing in with a QR code again after it "
          "failed");
}

enum _Stage { starting, showingCode, enteringCheckCode, signingIn, failed }

/// The new device's side: shows the QR code, takes the check code, then
/// hands [MatrixQrLoginFlow] to [onSignIn] (the login screen's usual
/// path: the account is added and what follows a login runs).
class QrLoginPanel extends StatefulWidget {
  const QrLoginPanel({
    super.key,
    required this.client,
    required this.authMetadata,
    required this.onSignIn,
    required this.onClose,
  });

  final matrix.Client client;
  final matrix.GetAuthMetadataResponse authMetadata;
  final Future<void> Function(MatrixQrLoginFlow flow) onSignIn;
  final VoidCallback onClose;

  @override
  State<QrLoginPanel> createState() => _QrLoginPanelState();
}

class _QrLoginPanelState extends State<QrLoginPanel> {
  _Stage stage = _Stage.starting;
  QrLoginInvite? invite;
  QrSecureChannel? channel;
  MatrixQrLoginFlow? flow;
  String? error;
  bool copied = false;
  bool disposed = false;
  final checkCode = TextEditingController();

  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    invite?.cancel();
    setState(() {
      stage = _Stage.starting;
      error = null;
      copied = false;
    });
    try {
      final endpoint = await matrixRendezvousEndpoint(widget.client);
      if (endpoint == null) {
        return fail(QrLoginStrings.errorQrLoginServerUnsupported);
      }
      final created =
          await QrLoginInvite.create(widget.client.httpClient, endpoint);
      if (disposed) return created.cancel();
      setState(() {
        invite = created;
        stage = _Stage.showingCode;
      });
      final accepted = await created.accept();
      if (disposed) return accepted.close();
      setState(() {
        channel = accepted;
        stage = _Stage.enteringCheckCode;
      });
    } on QrLoginException catch (e) {
      fail(e.error.message);
    } catch (_) {
      fail(QrLoginError.failed.message);
    }
  }

  void fail(String message) {
    if (disposed) return;
    setState(() {
      stage = _Stage.failed;
      error = message;
    });
  }

  Future<void> confirm() async {
    final typed = int.tryParse(checkCode.text.trim());
    final open = channel;
    if (typed == null || open == null) return;
    final started = MatrixQrLoginFlow(
        channel: open,
        typedCheckCode: typed,
        authMetadata: widget.authMetadata);
    setState(() {
      flow = started;
      stage = _Stage.signingIn;
    });
    // The login screen shows why it failed; this panel then closes.
    await widget.onSignIn(started);
    if (!disposed) widget.onClose();
  }

  void cancel() {
    invite?.cancel();
    flow?.cancel();
    channel?.close();
    widget.onClose();
  }

  @override
  void dispose() {
    disposed = true;
    invite?.cancel();
    flow?.cancel();
    checkCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        tiamat.Text.labelEmphasised(QrLoginButton.promptLoginWithQrCode),
        ...switch (stage) {
          _Stage.starting => [const Center(child: CircularProgressIndicator())],
          _Stage.showingCode => showCode(context),
          _Stage.enteringCheckCode => enterCheckCode(),
          _Stage.signingIn => [signingIn()],
          _Stage.failed => [
              tiamat.Text.label(error ?? QrLoginError.failed.message),
              tiamat.Button.secondary(
                  key: const ValueKey('qr-login-retry'),
                  text: QrLoginStrings.promptQrLoginTryAgain,
                  onTap: start),
            ],
        },
        tiamat.Button.secondary(
          key: const ValueKey('qr-login-cancel'),
          text: CommonStrings.promptCancel,
          onTap: cancel,
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  List<Widget> showCode(BuildContext context) {
    final qr = invite!.qrCode;
    final text = qr.toText();
    return [
      tiamat.Text.labelLow(QrLoginStrings.labelQrLoginWaitingForScan),
      Center(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(8),
          child: SizedBox.square(
            dimension: 200,
            child: PrettyQrView(
              key: const ValueKey('qr-login-code'),
              // The payload is binary: byte mode, not a UTF-8 string.
              qrImage: QrImage(QrCode.fromUint8List(
                  data: qr.toBytes(),
                  errorCorrectLevel: QrErrorCorrectLevel.L)),
              decoration: const PrettyQrDecoration(
                shape: PrettyQrSquaresSymbol(color: Colors.black),
                background: Colors.white,
              ),
            ),
          ),
        ),
      ),
      SelectableText(text,
          key: const ValueKey('qr-login-text'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
      Center(
        child: tiamat.Button.secondary(
          text: copied
              ? CommonStrings.promptCopyComplete
              : DeviceAuthPanel.promptDeviceAuthCopyCode,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (mounted) setState(() => copied = true);
          },
        ),
      ),
    ];
  }

  List<Widget> enterCheckCode() => [
        tiamat.Text.label(QrLoginStrings.labelQrLoginEnterCheckCode),
        TextField(
          key: const ValueKey('qr-login-check-code'),
          controller: checkCode,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 2,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
              labelText: QrLoginStrings.labelQrLoginCheckCodeField),
          onSubmitted: (_) => confirm(),
        ),
        tiamat.Button(
          key: const ValueKey('qr-login-confirm'),
          text: CommonStrings.promptConfirm,
          onTap: confirm,
        ),
      ];

  Widget signingIn() => ValueListenableBuilder<QrLoginStep>(
        valueListenable: flow!.step,
        builder: (context, step, _) => Column(
          spacing: 10,
          children: [
            tiamat.Text.labelLow(switch (step) {
              QrLoginStep.signingIn => QrLoginStrings.labelQrLoginSigningIn,
              QrLoginStep.sharingKeys ||
              QrLoginStep.done =>
                QrLoginStrings.labelQrLoginSharingKeys,
              _ => QrLoginStrings.labelQrLoginWaitingForApproval,
            }),
            const CircularProgressIndicator(),
          ],
        ),
      );
}
