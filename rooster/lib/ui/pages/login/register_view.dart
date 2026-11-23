import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' hide LoginFlow;
import 'package:rooster/client/auth.dart';
import 'package:rooster/client/client.dart' as rooster;
import 'package:rooster/client/matrix/auth/matrix_account_lifecycle.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/config/build_config.dart';
import 'package:rooster/ui/pages/matrix/authentication/uia_dialog_prompter.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Creates an account with the legacy API (`POST /v3/register`), going
/// through the steps the server asks. Pops true once signed in.
class RegisterView extends StatefulWidget {
  const RegisterView({super.key, required this.lifecycle, this.prompter});
  final MatrixAccountLifecycle lifecycle;

  /// Asks the server's steps; dialogs when null.
  final UiaPrompter? prompter;

  static String get promptLoginCreateAccount => Intl.message("Create account",
      name: "promptLoginCreateAccount",
      desc: "Link on the login screen, title and button of the form that "
          "creates a new account on the server typed");

  static String get labelRegisterUsername => Intl.message("Username",
      name: "labelRegisterUsername",
      desc: "Field of the form that creates an account: the name it will "
          "have on the server");

  static String get labelRegisterPassword => Intl.message("Password",
      name: "labelRegisterPassword",
      desc: "Field of the form that creates an account");

  static String get labelRegisterConfirmPassword =>
      Intl.message("Confirm password",
          name: "labelRegisterConfirmPassword",
          desc: "Field where a new password is typed a second time");

  static String get errorPasswordsDiffer =>
      Intl.message("The passwords do not match.",
          name: "errorPasswordsDiffer",
          desc: "Under a form where a new password is typed twice, when the "
              "two differ");

  static String get errorRegisterUserInUse =>
      Intl.message("That username is taken. Pick another.",
          name: "errorRegisterUserInUse",
          desc: "Creating an account failed: the server has an account "
              "with that name");

  static String get errorRegisterInvalidUsername => Intl.message(
      "That username cannot be used. Use lowercase letters, numbers, and . _ = - / only.",
      name: "errorRegisterInvalidUsername",
      desc: "Creating an account failed: the name has characters Matrix "
          "does not allow; keep the list of characters as it is");

  static String get errorRegisterExclusive =>
      Intl.message("That username is reserved on this server. Pick another.",
          name: "errorRegisterExclusive",
          desc: "Creating an account failed: the name belongs to a bridge or "
              "service of the server");

  static String get errorRegisterWeakPassword =>
      Intl.message("That password is too weak. Pick a longer one.",
          name: "errorRegisterWeakPassword",
          desc: "Creating an account or changing the password failed: the "
              "server finds the password too weak");

  static String get errorRegisterDisabled =>
      Intl.message("This server does not let new accounts sign up here.",
          name: "errorRegisterDisabled",
          desc: "Creating an account failed: the server has registration "
              "turned off");

  static String errorRegisterFailed(String reason) =>
      Intl.message("Could not create the account: $reason",
          name: "errorRegisterFailed",
          args: [reason],
          desc: "Creating an account failed for another reason, with the "
              "server's message");

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final username = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> submit() async {
    if (password.text != confirm.text) {
      return setState(() => error = RegisterView.errorPasswordsDiffer);
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.lifecycle.register(
          username: username.text.trim(),
          password: password.text,
          deviceName: BuildConfig.appName,
          prompter: widget.prompter ?? DialogUiaPrompter(context));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = registrationErrorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        for (final (key, controller, label, obscure) in [
          (
            'register-username',
            username,
            RegisterView.labelRegisterUsername,
            false
          ),
          (
            'register-password',
            password,
            RegisterView.labelRegisterPassword,
            true
          ),
          (
            'register-confirm',
            confirm,
            RegisterView.labelRegisterConfirmPassword,
            true
          ),
        ])
          TextField(
            key: ValueKey(key),
            controller: controller,
            obscureText: obscure,
            autocorrect: false,
            readOnly: busy,
            decoration: InputDecoration(
                border: const OutlineInputBorder(), labelText: label),
          ),
        if (error != null)
          tiamat.Text.error(error!, key: const ValueKey('register-error')),
        tiamat.Button(
          text: RegisterView.promptLoginCreateAccount,
          isLoading: busy,
          onTap: busy ? null : submit,
        ),
      ],
    );
  }
}

/// Signs in the account [RegisterView] just created. Registration leaves
/// the Matrix client signed in already, so this only reports it: run
/// through [rooster.Client.executeLoginFlow], the account is kept for the
/// next start and gets everything that follows any other login.
class RegisteredAccountLoginFlow implements LoginFlow {
  const RegisteredAccountLoginFlow();

  @override
  Future<rooster.LoginResult> submit(rooster.Client client) async =>
      client is MatrixClient && client.matrixClient.isLogged()
          ? rooster.LoginResultSuccess()
          : rooster.LoginResultFailed();
}

/// What the person reads when creating an account failed; null when they
/// closed a step themselves.
String? registrationErrorText(Object error) =>
    switch (RegistrationError.of(error)) {
      RegistrationError.cancelled => null,
      RegistrationError.userInUse => RegisterView.errorRegisterUserInUse,
      RegistrationError.invalidUsername =>
        RegisterView.errorRegisterInvalidUsername,
      RegistrationError.exclusive => RegisterView.errorRegisterExclusive,
      RegistrationError.weakPassword => RegisterView.errorRegisterWeakPassword,
      RegistrationError.disabled => RegisterView.errorRegisterDisabled,
      RegistrationError.other => error is UiaUnsupportedException
          ? DialogUiaPrompter.errorUiaUnsupported
          : RegisterView.errorRegisterFailed(
              error is MatrixException ? error.errorMessage : '$error'),
    };
