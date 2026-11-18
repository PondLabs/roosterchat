import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rooster/client/alert.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/matrix/authentication/matrix_uia_request.dart';
import 'package:rooster/ui/pages/matrix/verification/matrix_verification_page.dart';
import 'package:rooster/ui/pages/matrix/verification/verify_this_device.dart';

import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixKeyVerificationComponent
    implements Component<MatrixClient>, NeedsPostLoginInit {
  static String get labelAppVerificationRequest =>
      Intl.message("Verification Request",
          name: "labelAppVerificationRequest",
          desc: "Title of the dialog that opens when another session or "
              "person asks to verify this session");

  static String get labelAppAuthenticationRequest =>
      Intl.message("Authentication Request",
          name: "labelAppAuthenticationRequest",
          desc: "Title of the dialog that opens when the server asks you to "
              "confirm who you are (your password) before an action");

  static String get labelDeviceNotVerified =>
      Intl.message("This device is not verified",
          name: "labelDeviceNotVerified",
          desc: "Title of the notice in the Home screen's alerts while this "
              "device (session) has not been verified with the account's "
              "cross-signing");

  static String get messageDeviceNotVerified => Intl.message(
      "Encrypted messages won't open here until you verify this device. Tap to verify.",
      name: "messageDeviceNotVerified",
      desc: "Under 'This device is not verified' in the Home screen's "
          "alerts; tapping the notice opens the ways to verify this device");

  /// Whether this device must be verified before it can read encrypted
  /// messages: the account has cross-signing (a master key), and with the
  /// SDK's `ShareKeysWith.crossVerifiedIfEnabled` others then send room keys
  /// only to the devices it signed. This one is not signed.
  static bool needsVerification(matrix.Client client) =>
      client.isLogged() &&
      client.encryptionEnabled &&
      client.userDeviceKeys[client.userID]?.masterKey != null &&
      client.isUnknownSession;

  @override
  MatrixClient client;

  MatrixKeyVerificationComponent(this.client);

  /// [needsVerification], as of the last [check]: the prompt and the
  /// undecrypted messages' line follow it.
  final ValueNotifier<bool> needed = ValueNotifier(false);

  /// The notice in the Home screen's alerts while [needed].
  Alert? _alert;

  /// Set by a fresh login: the prompt opens once, as soon as this device's
  /// keys are known.
  bool _askOnce = false;

  final List<StreamSubscription> _subscriptions = [];

  /// Opens the prompt once this device's keys are known, if it has to be
  /// verified. Called by a fresh login, before [postLoginInit].
  void askAfterLogin() => _askOnce = true;

  @override
  void postLoginInit() {
    Log.i("Registering key verification listeners");
    client.matrixClient.onKeyVerificationRequest.stream.listen((event) {
      AdaptiveDialog.show(
        navigator.currentContext!,
        builder: (_) => MatrixVerificationPage(request: event),
        title: labelAppVerificationRequest,
      );
    });

    client.matrixClient.onUiaRequest.stream.listen((event) {
      if (event.state == matrix.UiaRequestState.waitForUser) {
        AdaptiveDialog.show(
          navigator.currentContext!,
          builder: (_) => MatrixUIARequest(event, client),
          title: labelAppAuthenticationRequest,
        );
      }
    });

    if (_subscriptions.isEmpty) {
      _subscriptions
          .add(client.matrixClient.onSync.stream.listen((_) => check()));
      _subscriptions.add(client.matrixClient.onLoginStateChanged.stream
          .where((state) => state == matrix.LoginState.loggedOut)
          .listen((_) => check()));
    }
    check();
  }

  /// Brings [needed], the notice and the prompt after a login up to date
  /// with this device's keys.
  void check() {
    final mx = client.matrixClient;
    final need = needsVerification(mx);
    needed.value = need;

    final alerts = clientManager?.alertManager;
    if (need && _alert == null) {
      final alert = _alert = Alert(
        AlertType.warning,
        titleGetter: () => labelDeviceNotVerified,
        messageGetter: () => messageDeviceNotVerified,
        action: (context) => VerifyThisDevice.show(context, client),
      );
      alerts?.addAlert(alert);
    } else if (!need && _alert != null) {
      alerts?.clearAlert(_alert!);
      _alert = null;
    }

    // Decided once this device's keys are in: before that an account with
    // cross-signing looks like one without.
    final keysKnown = mx.userDeviceKeys[mx.userID]?.outdated == false;
    if (_askOnce && (need || keysKnown)) {
      _askOnce = false;
      final context = navigator.currentContext;
      if (need && context != null) VerifyThisDevice.show(context, client);
    }
  }

  /// Asks the homeserver for this account's keys again and runs [check]:
  /// after this device signed itself, without waiting for the next sync
  /// to say the keys changed.
  Future<void> refresh() async {
    final mx = client.matrixClient;
    try {
      mx.userDeviceKeys[mx.userID]?.outdated = true;
      await mx.updateUserDeviceKeys();
    } catch (error, stack) {
      Log.onError(error, stack, content: "Could not refresh own device keys");
    }
    check();
  }
}
