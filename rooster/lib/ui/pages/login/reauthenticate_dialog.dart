import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/client/auth.dart';
import 'package:rooster/client/matrix/auth/matrix_sso_login_flow.dart';
import 'package:rooster/client/matrix/auth/matrix_token_refresher.dart';
import 'package:rooster/client/matrix/auth/matrix_username_password_login_flow.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Signs an account's device in again when its refresh token was refused,
/// in place: the same device, its database and its encryption keys stay.
class ReauthenticateDialog extends StatefulWidget {
  const ReauthenticateDialog({super.key, required this.client});

  final MatrixClient client;

  static final Set<MatrixClient> _open = {};

  /// Opens the dialog for [client], once at a time.
  static Future<void> show(BuildContext context, MatrixClient client) async {
    if (!_open.add(client)) return;
    try {
      await AdaptiveDialog.show(
        context,
        title: labelReauthenticateTitle,
        builder: (_) => ReauthenticateDialog(client: client),
      );
    } finally {
      _open.remove(client);
    }
  }

  static String get labelReauthenticateTitle => Intl.message("Sign in again",
      name: "labelReauthenticateTitle",
      desc: "Title of the dialog, and of the alert on the Home screen, when "
          "the server no longer accepts this device's session and the person "
          "has to sign in again");

  static String get messageReauthenticateAlert => Intl.message(
      "Your session on this device has ended. Your messages and encryption "
      "keys are still here: sign in again to keep using them.",
      name: "messageReauthenticateAlert",
      desc: "Alert on the Home screen when the server no longer accepts this "
          "device's session; tapping it opens the dialog to sign in again");

  static String messageReauthenticate(String user) => Intl.message(
      "The session of $user on this device has ended. Sign in again to go on "
      "where you left off: this device keeps its messages and encryption "
      "keys.",
      name: "messageReauthenticate",
      args: [user],
      desc: "In the dialog to sign in again, when the server no longer "
          "accepts this device's session; user is the account's Matrix ID");

  static String get messageReauthenticateNoMethod => Intl.message(
      "Rooster cannot sign this device in again from here yet. You can try "
      "again later; nothing was deleted from this device.",
      name: "messageReauthenticateNoMethod",
      desc: "In the dialog to sign in again, when the server offers no way to "
          "sign this same device in again (a server that signs in through "
          "its own page)");

  static String get labelReauthenticatePassword => Intl.message("Password",
      name: "labelReauthenticatePassword",
      desc: "Label of the password field in the dialog to sign in again");

  static String get promptReauthenticate => Intl.message("Sign in",
      name: "promptReauthenticate",
      desc: "Button in the dialog to sign in again, under the password");

  static String promptReauthenticateSso(String provider) =>
      Intl.message("Continue with $provider",
          name: "promptReauthenticateSso",
          args: [provider],
          desc: "Button in the dialog to sign in again through single sign-on; "
              "provider is the sign-in provider's name, or the word for the "
              "server's own sign-in");

  static String get promptReauthenticateRetry => Intl.message("Try again",
      name: "promptReauthenticateRetry",
      desc: "Button in the dialog to sign in again that asks the server to "
          "renew the session once more, without a password");

  static String get promptReauthenticateLater => Intl.message("Not now",
      name: "promptReauthenticateLater",
      desc: "Button that closes the dialog to sign in again; the alert on the "
          "Home screen opens it again");

  static String get errorReauthenticateOtherDevice => Intl.message(
      "The server signed in another account or device, so nothing changed "
      "here. Sign in with this account.",
      name: "errorReauthenticateOtherDevice",
      desc: "In the dialog to sign in again, when the server answered for "
          "another account or another device than this one");

  @override
  State<ReauthenticateDialog> createState() => _ReauthenticateDialogState();
}

class _ReauthenticateDialogState extends State<ReauthenticateDialog> {
  final TextEditingController _password = TextEditingController();
  List<LoginFlow>? _flows;
  bool _busy = false;
  String? _error;

  MatrixTokenRefresher get _refresher => widget.client.tokenRefresher;

  @override
  void initState() {
    super.initState();
    widget.client.reauthenticationFlows().then((flows) {
      if (mounted) setState(() => _flows = flows);
    }).catchError((Object e, StackTrace s) {
      Log.onError(e, s, content: "Could not read the server's sign-in ways");
      if (mounted) setState(() => _flows = const []);
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ReauthenticationMismatch {
      _error = ReauthenticateDialog.errorReauthenticateOtherDevice;
    } on matrix.MatrixException catch (e) {
      _error = e.errorMessage;
    } on PlatformException catch (e) {
      // The person closed the single sign-on page.
      if (e.code != "CANCELED") _error = errorLoginUnknown;
    } catch (e, s) {
      Log.onError(e, s, content: "Could not sign the device in again");
      _error = errorLoginUnknown;
    }
    if (!mounted) return;
    if (_refresher.state.value == TokenRefreshState.active) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = false);
  }

  Future<void> _signInWithPassword() async {
    if (_password.text.isEmpty) {
      setState(() => _error = errorLoginEnterPassword);
      return;
    }
    await _run(() => _refresher.reauthenticate(password: _password.text));
  }

  Future<void> _signInWithSso(MatrixSSOLoginFlow flow) => _run(() async {
        final token =
            await flow.obtainLoginToken(widget.client.getMatrixClient());
        if (token != null) await _refresher.reauthenticate(loginToken: token);
      });

  @override
  Widget build(BuildContext context) {
    final flows = _flows;
    final user = widget.client.getMatrixClient().userID ?? "";
    final password = flows?.whereType<MatrixPasswordLoginFlow>() ?? [];
    final sso = flows?.whereType<MatrixSSOLoginFlow>() ?? [];
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          tiamat.Text.label(ReauthenticateDialog.messageReauthenticate(user)),
          if (flows == null)
            const Center(child: CircularProgressIndicator())
          else if (flows.isEmpty)
            tiamat.Text.label(
                ReauthenticateDialog.messageReauthenticateNoMethod),
          if (password.isNotEmpty) ...[
            TextField(
              key: const ValueKey('reauthenticate-password'),
              controller: _password,
              obscureText: true,
              enabled: !_busy,
              autofocus: true,
              onSubmitted: (_) => _signInWithPassword(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: ReauthenticateDialog.labelReauthenticatePassword,
              ),
            ),
            tiamat.Button(
              key: const ValueKey('reauthenticate-submit'),
              text: ReauthenticateDialog.promptReauthenticate,
              isLoading: _busy,
              onTap: _busy ? null : _signInWithPassword,
            ),
          ],
          for (final flow in sso)
            tiamat.Button.secondary(
              text: ReauthenticateDialog.promptReauthenticateSso(flow.name),
              onTap: _busy ? null : () => _signInWithSso(flow),
            ),
          if (_error != null)
            tiamat.Text.error(_error!, key: const ValueKey('reauth-error')),
          tiamat.Button.secondary(
            key: const ValueKey('reauthenticate-retry'),
            text: ReauthenticateDialog.promptReauthenticateRetry,
            onTap: _busy ? null : () => _run(() => _refresher.retry()),
          ),
          tiamat.Button.secondary(
            text: ReauthenticateDialog.promptReauthenticateLater,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
