import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rooster/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The login screen's OAuth 2.0 buttons: sign in on the server's page, and
/// "Create account" when the server opens its registration page for apps
/// (`prompt=create`).
class OidcLoginButtons extends StatelessWidget {
  const OidcLoginButtons({
    super.key,
    required this.flows,
    required this.onLogin,
  });

  final List<MatrixOidcLoginFlow> flows;
  final void Function(MatrixOidcLoginFlow flow) onLogin;

  static String promptLoginOauth(String server) =>
      Intl.message("Sign in with $server",
          name: "promptLoginOauth",
          args: [server],
          desc: "Button on the login screen that opens the homeserver's own "
              "sign-in page in the browser; the server is its address, such as "
              "matrix.org");

  static String get promptLoginOauthCreateAccount => Intl.message(
      "Create account",
      name: "promptLoginOauthCreateAccount",
      desc: "Button on the login screen that opens the homeserver's page for "
          "making a new account, in the browser");

  @override
  Widget build(BuildContext context) {
    final signIn = flows.where((f) => !f.createAccount).firstOrNull;
    final create = flows.where((f) => f.createAccount).firstOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        if (signIn != null)
          SizedBox(
            height: 50,
            child: tiamat.Button(
              text: promptLoginOauth(signIn.serverName),
              onTap: () => onLogin(signIn),
            ),
          ),
        if (create != null)
          tiamat.Button.secondary(
            text: promptLoginOauthCreateAccount,
            onTap: () => onLogin(create),
          ),
      ],
    );
  }
}
