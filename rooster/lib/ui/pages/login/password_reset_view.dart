import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:rooster/client/matrix/auth/matrix_account_lifecycle.dart';
import 'package:rooster/ui/pages/login/register_view.dart';
import 'package:rooster/ui/pages/matrix/authentication/uia_dialog_prompter.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Resets a forgotten password by email: the server sends a link
/// (`requestToken`), and once it is opened the new password is set.
class PasswordResetView extends StatefulWidget {
  const PasswordResetView({super.key, required this.lifecycle});
  final MatrixAccountLifecycle lifecycle;

  static String get promptLoginForgotPassword =>
      Intl.message("Forgot password?",
          name: "promptLoginForgotPassword",
          desc: "Link on the login screen to reset the password by email");

  static String get labelPasswordReset => Intl.message("Reset password",
      name: "labelPasswordReset",
      desc: "Title of the dialog that resets a forgotten password by email");

  static String get messagePasswordResetEmail => Intl.message(
      "Enter the email address on your account. The server will send you a link.",
      name: "messagePasswordResetEmail",
      desc: "First step of resetting a forgotten password");

  static String get promptPasswordResetSend => Intl.message("Send link",
      name: "promptPasswordResetSend",
      desc: "Button that asks the server to email a password reset link");

  static String messagePasswordResetSent(String email) => Intl.message(
      "We sent a link to $email. Open it, then choose a new password here.",
      name: "messagePasswordResetSent",
      args: [email],
      desc: "Second step of resetting a forgotten password, with the email "
          "address the link went to");

  static String get labelNewPassword => Intl.message("New password",
      name: "labelNewPassword",
      desc: "Field for the new password when resetting or changing it");

  static String get labelSignOutOtherSessions =>
      Intl.message("Sign out of my other sessions",
          name: "labelSignOutOtherSessions",
          desc: "Checkbox when setting a new password: also sign out every "
              "other device signed in to the account");

  static String get errorPasswordResetNotConfirmed => Intl.message(
      "The link was not opened yet, or it expired. Open the latest email, or send a new link.",
      name: "errorPasswordResetNotConfirmed",
      desc: "Setting the new password failed because the server has not "
          "seen the emailed link opened, or the link expired");

  static String get promptPasswordResetSendAgain =>
      Intl.message("Send a new link",
          name: "promptPasswordResetSendAgain",
          desc: "Button to email the password reset link again");

  static String get errorPasswordResetNoAccount =>
      Intl.message("No account on this server uses that email address.",
          name: "errorPasswordResetNoAccount",
          desc: "Sending the password reset link failed: the address is on "
              "no account");

  static String get messagePasswordResetDone =>
      Intl.message("Your password was changed. You can log in with it now.",
          name: "messagePasswordResetDone",
          desc: "Last step of resetting a forgotten password");

  @override
  State<PasswordResetView> createState() => _PasswordResetViewState();
}

class _PasswordResetViewState extends State<PasswordResetView> {
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  ThreepidValidation? validation;
  bool signOutEverywhere = true;
  bool done = false;
  bool busy = false;
  String? error;

  Future<void> attempt(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on PasswordResetNotConfirmedException {
      error = PasswordResetView.errorPasswordResetNotConfirmed;
    } on MatrixException catch (e) {
      error = switch (e.errcode) {
        'M_THREEPID_NOT_FOUND' => PasswordResetView.errorPasswordResetNoAccount,
        'M_WEAK_PASSWORD' => RegisterView.errorRegisterWeakPassword,
        _ => e.errorMessage,
      };
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> send() => attempt(() async {
        final sent = await widget.lifecycle
            .requestPasswordReset(email.text.trim(), again: validation);
        validation = sent;
      });

  Future<void> reset() async {
    if (password.text != confirm.text) {
      return setState(() => error = RegisterView.errorPasswordsDiffer);
    }
    await attempt(() async {
      await widget.lifecycle.resetPassword(validation!, password.text,
          logoutDevices: signOutEverywhere);
      done = true;
    });
  }

  Widget field(String key, TextEditingController controller, String label,
          {bool obscure = true}) =>
      TextField(
        key: ValueKey(key),
        controller: controller,
        obscureText: obscure,
        autocorrect: false,
        readOnly: busy,
        decoration: InputDecoration(
            border: const OutlineInputBorder(), labelText: label),
      );

  @override
  Widget build(BuildContext context) {
    final sent = validation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (done) ...[
          tiamat.Text.label(PasswordResetView.messagePasswordResetDone),
          tiamat.Button(
              text: CommonStrings.promptClose,
              onTap: () => Navigator.of(context).pop(true)),
        ] else if (sent == null) ...[
          tiamat.Text.labelLow(PasswordResetView.messagePasswordResetEmail),
          field('reset-email', email, DialogUiaPrompter.labelUiaEmail,
              obscure: false),
        ] else ...[
          tiamat.Text.labelLow(
              PasswordResetView.messagePasswordResetSent(sent.address)),
          field('reset-password', password, PasswordResetView.labelNewPassword),
          field('reset-confirm', confirm,
              RegisterView.labelRegisterConfirmPassword),
          CheckboxListTile(
            value: signOutEverywhere,
            title: Text(PasswordResetView.labelSignOutOtherSessions),
            onChanged: (value) =>
                setState(() => signOutEverywhere = value == true),
          ),
        ],
        if (error != null)
          tiamat.Text.error(error!, key: const ValueKey('reset-error')),
        if (!done)
          tiamat.Button(
            text: sent == null
                ? PasswordResetView.promptPasswordResetSend
                : CommonStrings.promptConfirm,
            isLoading: busy,
            onTap: busy ? null : (sent == null ? send : reset),
          ),
        if (sent != null && !done)
          tiamat.Button.secondary(
            text: PasswordResetView.promptPasswordResetSendAgain,
            onTap: busy ? null : send,
          ),
      ],
    );
  }
}
