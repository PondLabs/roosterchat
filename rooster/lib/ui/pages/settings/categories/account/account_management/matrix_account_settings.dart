import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:rooster/client/matrix/auth/matrix_account_lifecycle.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/login/password_reset_view.dart';
import 'package:rooster/ui/pages/login/register_view.dart';
import 'package:rooster/ui/pages/matrix/authentication/uia_dialog_prompter.dart';
import 'package:rooster/utils/common_strings.dart';
import 'package:rooster/utils/links/link_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The account itself, for one Matrix account: on a server with an account
/// page (OAuth 2.0, MSC4191) the links to what that page announces; on
/// other servers the password, email addresses and phone numbers, sign-in
/// codes and deactivation, through the client API.
class MatrixAccountSettings extends StatefulWidget {
  const MatrixAccountSettings(
      {super.key, required this.lifecycle, this.onDeactivated, this.prompter});
  final MatrixAccountLifecycle lifecycle;
  final VoidCallback? onDeactivated;

  /// Asks the server's confirmation steps; dialogs when null.
  final UiaPrompter? prompter;

  static String get labelAccountSettings => Intl.message("Account settings",
      name: "labelAccountSettings",
      desc: "Settings > Manage Accounts: button on an account, and the title "
          "of what it opens (password, email addresses, deactivation)");

  static String get messageAccountOnWebsite =>
      Intl.message("Your server manages this account on its own website.",
          name: "messageAccountOnWebsite",
          desc: "Account settings of an account on a server with an account "
              "website: the buttons below open that website");

  static String get promptAccountManage => Intl.message("Manage account",
      name: "promptAccountManage",
      desc: "Opens the server's account website on its main page");

  static String get promptAccountProfile => Intl.message("Profile",
      name: "promptAccountProfile",
      desc: "Opens the server's account website on the account's profile");

  static String get promptAccountSessions => Intl.message("Sessions",
      name: "promptAccountSessions",
      desc: "Opens the server's account website on the list of signed-in "
          "devices");

  static String get promptAccountResetIdentity =>
      Intl.message("Reset encryption identity",
          name: "promptAccountResetIdentity",
          desc: "Opens the server's account website where the keys that "
              "verify the account's sessions (cross-signing) can be reset");

  static String get promptChangePassword => Intl.message("Change password",
      name: "promptChangePassword",
      desc: "Account settings: button, and title of the dialog it opens");

  static String get labelCurrentPassword => Intl.message("Current password",
      name: "labelCurrentPassword",
      desc: "Field in the Change password dialog");

  static String get messagePasswordChanged =>
      Intl.message("Your password was changed.",
          name: "messagePasswordChanged",
          desc: "Account settings, after changing the password");

  static String get labelAccountThreepids =>
      Intl.message("Email addresses and phone numbers",
          name: "labelAccountThreepids",
          desc: "Account settings: header of the account's email addresses "
              "and phone numbers");

  static String get promptAddEmail => Intl.message("Add email address",
      name: "promptAddEmail", desc: "Account settings: button");

  static String get promptAddPhone => Intl.message("Add phone number",
      name: "promptAddPhone", desc: "Account settings: button");

  static String get tooltipThreepidUnbind =>
      Intl.message("Stop people finding you by this address",
          name: "tooltipThreepidUnbind",
          desc: "Account settings: button on an email address or phone "
              "number that unlinks it from the identity server, where people "
              "look accounts up, and keeps it on the account");

  static String get errorThreepidNotConfirmed => Intl.message(
      "The address was not confirmed yet. Open the link, then try again.",
      name: "errorThreepidNotConfirmed",
      desc: "Adding an email address failed because its confirmation link "
          "was not opened");

  static String get errorThreepidInUse =>
      Intl.message("That address is already on an account.",
          name: "errorThreepidInUse",
          desc: "Adding an email address or phone number failed: another "
              "account on the server has it");

  static String get promptLoginToken => Intl.message("Sign in another device",
      name: "promptLoginToken",
      desc: "Account settings: button that makes a one-time sign-in code");

  static String messageLoginToken(int minutes) => Intl.plural(minutes,
      one: "This code signs in one device, once, within 1 minute.",
      other: "This code signs in one device, once, within $minutes minutes.",
      name: "messageLoginToken",
      args: [minutes],
      desc: "Under a one-time sign-in code made in Account settings, how "
          "long it lasts");

  static String get labelDeactivateAccount => Intl.message("Deactivate account",
      name: "labelDeactivateAccount",
      desc: "Account settings: button, title of the dialog it opens and its "
          "final button");

  static String get messageDeactivateWarning => Intl.message(
      "Deactivating is permanent: you cannot sign in again, and nobody can take this username.",
      name: "messageDeactivateWarning",
      desc: "Warning in the Deactivate account dialog");

  static String get labelDeactivateErase =>
      Intl.message("Also erase my messages for people who join rooms later",
          name: "labelDeactivateErase",
          desc: "Checkbox in the Deactivate account dialog (Matrix's erase)");

  static String get labelDeactivateConfirm =>
      Intl.message("I understand that this cannot be undone",
          name: "labelDeactivateConfirm",
          desc: "Checkbox in the Deactivate account dialog that must be "
              "ticked before the account can be deactivated");

  @override
  State<MatrixAccountSettings> createState() => _MatrixAccountSettingsState();
}

class _MatrixAccountSettingsState extends State<MatrixAccountSettings> {
  MatrixAccountLifecycle get lifecycle => widget.lifecycle;
  UiaPrompter get prompter => widget.prompter ?? DialogUiaPrompter(context);

  bool loading = true;
  GetAuthMetadataResponse? metadata;
  List<ThirdPartyIdentifier> threepids = const [];
  bool loginTokens = false;
  String? message;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      metadata = await lifecycle.api.getAuthMetadata();
    } catch (_) {
      // No OAuth 2.0 API here (404 M_UNRECOGNIZED).
    }
    if (metadata?.accountManagementUri == null) {
      await run(() async {
        threepids = await lifecycle.threepids();
        loginTokens = await lifecycle.canGenerateLoginToken();
      });
    }
    if (mounted) setState(() => loading = false);
  }

  /// Runs [action], then shows [done] or why it failed.
  Future<void> run(Future<void> Function() action, {String? done}) async {
    setState(() => error = message = null);
    try {
      await action();
      message = done;
    } catch (e, s) {
      error = switch (e) {
        UiaCancelledException() => null,
        UiaUnsupportedException() => DialogUiaPrompter.errorUiaUnsupported,
        MatrixException(errcode: 'M_THREEPID_AUTH_FAILED') =>
          MatrixAccountSettings.errorThreepidNotConfirmed,
        MatrixException(errcode: 'M_THREEPID_IN_USE') =>
          MatrixAccountSettings.errorThreepidInUse,
        MatrixException(errcode: 'M_WEAK_PASSWORD') =>
          RegisterView.errorRegisterWeakPassword,
        MatrixException e => e.errorMessage,
        _ => '$e',
      };
      if (error != null) Log.onError(e, s);
    }
    if (mounted) setState(() {});
  }

  Uri? link(String? action) => accountManagementLink(
      metadata?.accountManagementUri,
      metadata?.accountManagementActionsSupported,
      action: action);

  void open(Uri page) => LinkUtils.open(page,
      filterTrackingParameters: false, bypassConfirmation: true);

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final page = link(null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        if (message != null) tiamat.Text.label(message!),
        if (error != null)
          tiamat.Text.error(error!, key: const ValueKey('account-error')),
        if (page != null) ...[
          tiamat.Text.labelLow(MatrixAccountSettings.messageAccountOnWebsite),
          for (final (action, label) in [
            (
              AccountManagementActions.profile,
              MatrixAccountSettings.promptAccountProfile
            ),
            (
              AccountManagementActions.sessionsList,
              MatrixAccountSettings.promptAccountSessions
            ),
            (
              AccountManagementActions.crossSigningReset,
              MatrixAccountSettings.promptAccountResetIdentity
            ),
            (
              AccountManagementActions.accountDeactivate,
              MatrixAccountSettings.labelDeactivateAccount
            ),
          ])
            if (link(action) case final Uri url)
              tiamat.Button.secondary(text: label, onTap: () => open(url)),
          tiamat.Button(
              text: MatrixAccountSettings.promptAccountManage,
              onTap: () => open(page)),
        ] else
          ...legacy(),
      ],
    );
  }

  List<Widget> legacy() => [
        tiamat.Button.secondary(
            text: MatrixAccountSettings.promptChangePassword,
            onTap: changePassword),
        tiamat.Text.labelEmphasised(
            MatrixAccountSettings.labelAccountThreepids),
        for (final threepid in threepids)
          Row(children: [
            Expanded(child: tiamat.Text.label(threepid.address)),
            IconButton(
              tooltip: MatrixAccountSettings.tooltipThreepidUnbind,
              icon: const Icon(Icons.link_off),
              onPressed: () =>
                  run(() => lifecycle.unbindThreepid(threepid).then((_) {})),
            ),
            IconButton(
              tooltip: CommonStrings.promptRemove,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => run(() async {
                await lifecycle.removeThreepid(threepid);
                threepids = await lifecycle.threepids();
              }),
            ),
          ]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          tiamat.Button.secondary(
              text: MatrixAccountSettings.promptAddEmail, onTap: addEmail),
          tiamat.Button.secondary(
              text: MatrixAccountSettings.promptAddPhone, onTap: addPhone),
        ]),
        if (loginTokens)
          tiamat.Button.secondary(
              text: MatrixAccountSettings.promptLoginToken,
              onTap: makeLoginToken),
        tiamat.Button.danger(
            text: MatrixAccountSettings.labelDeactivateAccount,
            onTap: deactivateAccount),
      ];

  Future<void> changePassword() async {
    final changed = await AdaptiveDialog.show<bool>(context,
        title: MatrixAccountSettings.promptChangePassword,
        builder: (_) =>
            ChangePasswordView(lifecycle: lifecycle, prompter: prompter));
    if (changed == true) {
      setState(() => message = MatrixAccountSettings.messagePasswordChanged);
    }
  }

  Future<void> addEmail() => run(() async {
        final ask = DialogUiaPrompter(context);
        final address = await ask.email(failed: false);
        if (address == null) return;
        final validation = await lifecycle.requestThreepidValidation(
            ThirdPartyIdentifierMedium.email, address);
        if (!await ask.confirmEmail(address)) return;
        await lifecycle.addThreepid(validation, prompter);
        threepids = await lifecycle.threepids();
      });

  Future<void> addPhone() => run(() async {
        final ask = DialogUiaPrompter(context);
        final phone = await ask.phone(failed: false);
        if (phone == null) return;
        final validation = await lifecycle.requestThreepidValidation(
            ThirdPartyIdentifierMedium.msisdn, phone.$2,
            country: phone.$1);
        final code = await ask.smsCode(phone.$2);
        if (code == null) return;
        await lifecycle.submitPhoneCode(validation, code);
        await lifecycle.addThreepid(validation, prompter);
        threepids = await lifecycle.threepids();
      });

  Future<void> makeLoginToken() => run(() async {
        final token = await lifecycle.generateLoginToken(prompter);
        if (!mounted) return;
        await AdaptiveDialog.show(context,
            title: MatrixAccountSettings.promptLoginToken,
            builder: (context) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    SelectableText(token.loginToken),
                    tiamat.Text.labelLow(
                        MatrixAccountSettings.messageLoginToken(
                            (token.expiresInMs / 60000).ceil())),
                    tiamat.Button(
                        text: CommonStrings.promptCopy,
                        onTap: () => Clipboard.setData(
                            ClipboardData(text: token.loginToken))),
                  ],
                ));
      });

  Future<void> deactivateAccount() async {
    final deactivated = await AdaptiveDialog.show<bool>(context,
        title: MatrixAccountSettings.labelDeactivateAccount,
        builder: (_) =>
            DeactivateAccountView(lifecycle: lifecycle, prompter: prompter));
    if (deactivated == true) widget.onDeactivated?.call();
  }
}

/// The current password, the new one twice, and whether to sign out the
/// other sessions. Pops true once changed.
class ChangePasswordView extends StatefulWidget {
  const ChangePasswordView(
      {super.key, required this.lifecycle, required this.prompter});
  final MatrixAccountLifecycle lifecycle;
  final UiaPrompter prompter;

  @override
  State<ChangePasswordView> createState() => _ChangePasswordViewState();
}

class _ChangePasswordViewState extends State<ChangePasswordView> {
  final current = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool signOutEverywhere = false;
  String? error;

  Future<void> submit() async {
    if (password.text != confirm.text) {
      return setState(() => error = RegisterView.errorPasswordsDiffer);
    }
    try {
      await widget.lifecycle.changePassword(
          currentPassword: current.text,
          newPassword: password.text,
          logoutDevices: signOutEverywhere,
          prompter: widget.prompter);
      if (mounted) Navigator.of(context).pop(true);
    } on UiaCancelledException {
      return;
    } catch (e) {
      setState(() => error = e is MatrixException
          ? (e.errcode == 'M_WEAK_PASSWORD'
              ? RegisterView.errorRegisterWeakPassword
              : e.errorMessage)
          : '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        for (final (key, controller, label) in [
          (
            'password-current',
            current,
            MatrixAccountSettings.labelCurrentPassword
          ),
          ('password-new', password, PasswordResetView.labelNewPassword),
          (
            'password-confirm',
            confirm,
            RegisterView.labelRegisterConfirmPassword
          ),
        ])
          TextField(
            key: ValueKey(key),
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(
                border: const OutlineInputBorder(), labelText: label),
          ),
        CheckboxListTile(
          value: signOutEverywhere,
          title: Text(PasswordResetView.labelSignOutOtherSessions),
          onChanged: (value) =>
              setState(() => signOutEverywhere = value == true),
        ),
        if (error != null) tiamat.Text.error(error!),
        tiamat.Button(text: CommonStrings.promptConfirm, onTap: submit),
      ],
    );
  }
}

/// Deactivation, with Matrix's `erase`: the final button only works once
/// the person ticked that they understand it cannot be undone. Pops true
/// once the account is deactivated.
class DeactivateAccountView extends StatefulWidget {
  const DeactivateAccountView(
      {super.key, required this.lifecycle, required this.prompter});
  final MatrixAccountLifecycle lifecycle;
  final UiaPrompter prompter;

  @override
  State<DeactivateAccountView> createState() => _DeactivateAccountViewState();
}

class _DeactivateAccountViewState extends State<DeactivateAccountView> {
  bool erase = false;
  bool confirmed = false;
  bool busy = false;
  String? error;

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.lifecycle.deactivate(
          confirmed: confirmed, erase: erase, prompter: widget.prompter);
      if (mounted) Navigator.of(context).pop(true);
    } on UiaCancelledException {
      // Closed a step: nothing happened.
    } catch (e) {
      error = e is MatrixException ? e.errorMessage : '$e';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        tiamat.Text.label(MatrixAccountSettings.messageDeactivateWarning),
        CheckboxListTile(
          key: const ValueKey('deactivate-erase'),
          value: erase,
          title: Text(MatrixAccountSettings.labelDeactivateErase),
          onChanged: busy ? null : (v) => setState(() => erase = v == true),
        ),
        CheckboxListTile(
          key: const ValueKey('deactivate-confirm'),
          value: confirmed,
          title: Text(MatrixAccountSettings.labelDeactivateConfirm),
          onChanged: busy ? null : (v) => setState(() => confirmed = v == true),
        ),
        if (error != null) tiamat.Text.error(error!),
        tiamat.Button.danger(
          key: const ValueKey('deactivate-submit'),
          text: MatrixAccountSettings.labelDeactivateAccount,
          isLoading: busy,
          onTap: confirmed && !busy ? submit : null,
        ),
      ],
    );
  }
}
