import 'dart:async';

import 'package:rooster/client/auth.dart';
import 'package:rooster/client/client.dart';
import 'package:rooster/client/matrix/auth/matrix_account_lifecycle.dart';
import 'package:rooster/client/matrix/auth/matrix_device_auth_flow.dart';
import 'package:rooster/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/pages/login/login_page_view.dart';
import 'package:rooster/ui/pages/login/password_reset_view.dart';
import 'package:rooster/ui/pages/login/qr_code_login.dart';
import 'package:rooster/ui/pages/login/register_view.dart';
import 'package:rooster/utils/debounce.dart';
import 'package:rooster/utils/rng.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class LoginPage extends StatefulWidget {
  const LoginPage(
      {super.key,
      this.onSuccess,
      this.canNavigateBack = false,
      this.createClient});
  final bool canNavigateBack;
  final Function(Client loggedInClient)? onSuccess;

  /// Makes the client that signs in; [MatrixClient.create] when null. Tests
  /// give one on a fake homeserver.
  final Future<Client> Function(String internalId)? createClient;

  @override
  State<LoginPage> createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  String get messageLoginFailed => Intl.message(
        "Login Failed...",
        name: "messageLoginFailed",
        desc: "Generic text to show that an attempted login has failed",
      );

  String get messageAlreadyLoggedIn => Intl.message(
        "You have already logged in to this account",
        name: "messageAlreadyLoggedIn",
        desc:
            "An error message displayed when the user attempts to add an account which has already been logged in to on this device",
      );

  String get messageInvalidUsernameOrPassword => Intl.message(
      "Invalid username or password",
      name: "messageInvalidUsernameOrPassword",
      desc:
          "An error message displayed when the user attempts to log into an account using the wrong username/password combination");

  String get messageLoginCancelled => Intl.message("Login Cancelled",
      name: "messageLoginCancelled",
      desc: "In the dialog shown when signing in did not finish, when the "
          "person closed the sign-in page of their server");

  String get labelLoginFailed => Intl.message("Login failed",
      name: "labelLoginFailed",
      desc: "Title of the dialog shown when signing in did not work; the "
          "reason is under it");

  String get errorLoginBrowserStorage => Intl.message(
      "Could not open browser storage. Use HTTPS or localhost, then reload.",
      name: "errorLoginBrowserStorage",
      desc: "Under the homeserver field on the login screen in a browser, "
          "when the app cannot store anything: the page has to be served "
          "over HTTPS or from localhost, and reloaded");

  String get errorLoginHomeserverUnverified => Intl.message(
      "Could not verify the homeserver. Check the address and connection.",
      name: "errorLoginHomeserverUnverified",
      desc: "Under the homeserver field on the login screen when the address "
          "typed does not answer as a Matrix server");

  StreamSubscription? progressSubscription;
  double? progress;
  List<LoginFlow>? loginFlows;
  Client? loginClient;
  String? pendingHomeserver;
  String? serverInfoError;
  int homeserverRequestId = 0;
  matrix.GetAuthMetadataResponse? authMetadata;
  MatrixDeviceAuthFlow? deviceAuthFlow;
  bool qrLogin = false;

  final Debouncer homeserverUpdateDebouncer = Debouncer(
    delay: const Duration(seconds: 1),
  );

  bool loadingServerInfo = false;
  bool isServerValid = false;
  bool isLoggingIn = false;

  @override
  void initState() {
    var internalId = RandomUtils.getRandomString(20);
    _initializeLoginClient(internalId);

    super.initState();
  }

  Future<void> _initializeLoginClient(String internalId) async {
    try {
      final client =
          await (widget.createClient ?? MatrixClient.create)(internalId)
              .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      loginClient = client;

      progressSubscription = loginClient!.connectionStatusChanged.stream.listen(
        onLoginProgressChanged,
      );

      // The initial homeserver check can be scheduled before the Matrix client
      // is ready. Retry the latest value once initialization completes.
      if (pendingHomeserver != null && loadingServerInfo) {
        updateHomeserver(pendingHomeserver!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loadingServerInfo = false;
        serverInfoError = errorLoginBrowserStorage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoginPageView(
      canNavigateBack: widget.canNavigateBack,
      progress: progress,
      updateHomeserver: (value) {
        setState(() {
          loginFlows = null;
          isServerValid = false;
          loadingServerInfo = true;
          serverInfoError = null;
        });
        homeserverUpdateDebouncer.run(() => updateHomeserver(value));
      },
      flows: loginFlows,
      doSsoLogin: doSsoLogin,
      doOidcLogin: doOidcLogin,
      authMetadata: authMetadata,
      deviceAuthFlow: deviceAuthFlow,
      doDeviceLogin: doDeviceLogin,
      doQrLogin: doQrLogin,
      qrLoginPanel: qrLoginPanel(),
      doPasswordLogin: doPasswordLogin,
      isLoggingIn: isLoggingIn,
      loadingServerInfo: loadingServerInfo,
      hasSsoSupport: loginFlows?.whereType<SsoLoginFlow>().isNotEmpty == true,
      hasPasswordSupport:
          loginFlows?.whereType<PasswordLoginFlow>().isNotEmpty == true,
      isServerValid: isServerValid,
      serverInfoError: serverInfoError,
      onRegister: legacyAccountFlows ? doRegister : null,
      onForgotPassword: legacyAccountFlows ? doPasswordReset : null,
    );
  }

  /// Registration and password reset of the legacy API, on a server
  /// without OAuth 2.0 (which has its own pages for both).
  bool get legacyAccountFlows =>
      isServerValid &&
      authMetadata == null &&
      loginClient is MatrixClient &&
      loginFlows?.whereType<PasswordLoginFlow>().isNotEmpty == true;

  Future<void> doRegister() async {
    final client = loginClient;
    if (client is! MatrixClient) return;
    final registered = await AdaptiveDialog.show<bool>(context,
        title: RegisterView.promptLoginCreateAccount,
        builder: (_) => RegisterView(
            lifecycle: MatrixAccountLifecycle(client.matrixClient)));
    // As any other login: the account is kept for the next start, and what
    // follows a login (push, invitations, key verification) runs.
    if (registered == true) {
      await doLogin(
          () => client.executeLoginFlow(const RegisteredAccountLoginFlow()));
    }
  }

  void doPasswordReset() {
    final client = loginClient;
    if (client is! MatrixClient) return;
    AdaptiveDialog.show(context,
        title: PasswordResetView.labelPasswordReset,
        builder: (_) => PasswordResetView(
            lifecycle: MatrixAccountLifecycle(client.matrixClient)));
  }

  Future<void> doLogin(Future<LoginResult> Function() login) async {
    if (loginClient == null) return;
    if (isServerValid == false) {
      return;
    }

    setState(() {
      isLoggingIn = true;
    });

    LoginResult? result;

    try {
      result = await login();
    } catch (e, s) {
      // Said, not swallowed: a throw outside the flows' own handling (the
      // SSO flow, the profile fetch after the server accepted the login)
      // used to stop the spinner and show nothing, with a device already
      // made on the server.
      Log.onError(e, s, content: "Login threw");
      result = LoginResultError("$messageLoginFailed\n$e");
    }

    if (!mounted) return;

    if (!(result is LoginResultSuccess)) {
      setState(() {
        isLoggingIn = false;
      });
    }

    String? message = switch (result) {
      LoginResultSuccess _ => null,
      LoginResultError e => e.errorMessage,
      LoginResultCancelled _ => messageLoginCancelled,
      LoginResultAlreadyLoggedIn _ => messageAlreadyLoggedIn,
      LoginResultFailed _ => messageLoginFailed,
      LoginResult() => messageLoginFailed,
    };

    if (message != null) {
      if (mounted) {
        AdaptiveDialog.show(
          context,
          title: labelLoginFailed,
          builder: (_) => tiamat.Text(
            message,
          ),
        );
      }
    }

    if (result is LoginResultSuccess) {
      clientManager?.addClient(loginClient!);
      widget.onSuccess?.call(loginClient!);
    }
  }

  Future<void> doSsoLogin(SsoLoginFlow flow) async {
    if (loginClient == null) return;
    await doLogin(() => loginClient!.executeLoginFlow(flow));
  }

  Future<void> doOidcLogin(MatrixOidcLoginFlow flow) async {
    if (loginClient == null) return;
    await doLogin(() => loginClient!.executeLoginFlow(flow));
  }

  Future<void> doDeviceLogin() async {
    final metadata = authMetadata;
    if (loginClient == null || metadata == null || deviceAuthFlow != null) {
      return;
    }
    final flow = MatrixDeviceAuthFlow(authMetadata: metadata);
    setState(() => deviceAuthFlow = flow);
    try {
      await doLogin(() => loginClient!.executeLoginFlow(flow));
    } finally {
      flow.cancel();
      if (mounted) setState(() => deviceAuthFlow = null);
    }
  }

  void doQrLogin() {
    if (loginClient is! MatrixClient || authMetadata == null) return;
    setState(() => qrLogin = true);
  }

  /// QR code login (MSC4108): the panel shows the code, then signs in
  /// through [doLogin] like every other flow.
  Widget? qrLoginPanel() {
    final client = loginClient;
    final metadata = authMetadata;
    if (!qrLogin || client is! MatrixClient || metadata == null) return null;
    return QrLoginPanel(
      client: client.matrixClient,
      authMetadata: metadata,
      onSignIn: (flow) => doLogin(() => client.executeLoginFlow(flow)),
      onClose: () {
        if (mounted) setState(() => qrLogin = false);
      },
    );
  }

  Future<void> doPasswordLogin(
    PasswordLoginFlow flow,
    String username,
    String password,
  ) async {
    if (loginClient == null) return;
    flow.username = username;
    flow.password = password;

    await doLogin(() => loginClient!.executeLoginFlow(flow));
  }

  void onLoginProgressChanged(ClientConnectionStatusUpdate event) {
    if (!mounted) return;
    setState(() {
      progress = event.progress;
    });
  }

  Future<void> updateHomeserver(String input) async {
    pendingHomeserver = input;
    final requestId = ++homeserverRequestId;

    if (loginClient == null) {
      // Keep the spinner state until initState's client creation callback
      // retries this value.
      return;
    }

    setState(() {
      loginFlows = null;
      authMetadata = null;
      qrLogin = false;
      loadingServerInfo = true;
      isServerValid = false;
    });

    // An explicit scheme wins (plain-http homeservers on a LAN or in tests);
    // otherwise assume https like every other client.
    var uri = input.startsWith('http://') || input.startsWith('https://')
        ? Uri.parse(input)
        : Uri.https(input);
    var result = await loginClient!
        .setHomeserver(uri)
        .timeout(const Duration(seconds: 15), onTimeout: () => (false, null));

    if (!mounted || requestId != homeserverRequestId) return;

    setState(() {
      loadingServerInfo = false;
      isServerValid = result.$1;
      loginFlows = result.$2;
      final client = loginClient;
      authMetadata = client is MatrixClient ? client.authMetadata : null;
      serverInfoError = result.$1
          ? null
          : (client is MatrixClient ? client.homeserverError : null) ??
              errorLoginHomeserverUnverified;
    });
  }

  @override
  void dispose() {
    homeserverUpdateDebouncer.cancel();
    deviceAuthFlow?.cancel();
    progressSubscription?.cancel();
    super.dispose();
  }
}
