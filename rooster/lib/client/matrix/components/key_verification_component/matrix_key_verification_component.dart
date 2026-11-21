import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:rooster/client/alert.dart';
import 'package:rooster/client/components/component.dart';
import 'package:rooster/client/matrix/components/key_verification_component/matrix_qr_verification_payload.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/debug/log.dart';
import 'package:rooster/main.dart';
import 'package:rooster/ui/navigation/adaptive_dialog.dart';
import 'package:rooster/ui/pages/matrix/authentication/matrix_uia_request.dart';
import 'package:rooster/ui/pages/matrix/verification/matrix_verification_page.dart';
import 'package:rooster/ui/pages/matrix/verification/verify_this_device.dart';

import 'package:intl/intl.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixKeyVerificationComponent
    implements Component<MatrixClient>, NeedsPostLoginInit {
  /// Verification methods negotiated by Rooster: SAS (emoji and decimal)
  /// plus QR code show/scan and reciprocate (`m.qr_code.show.v1`,
  /// `m.qr_code.scan.v1`, `m.reciprocate.v1`).
  static const Set<KeyVerificationMethod> supportedVerificationMethods = {
    KeyVerificationMethod.emoji,
    KeyVerificationMethod.numbers,
    KeyVerificationMethod.qrShow,
    KeyVerificationMethod.qrScan,
    KeyVerificationMethod.reciprocate,
  };

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

  MatrixKeyVerificationComponent(this.client) {
    enableVerificationMethods();
  }

  /// Ensures the underlying Matrix SDK client negotiates SAS and QR code
  /// verification methods (`m.sas.v1`, `m.qr_code.show.v1`,
  /// `m.qr_code.scan.v1`, `m.reciprocate.v1`).
  void enableVerificationMethods() {
    client.matrixClient.verificationMethods = {
      ...client.matrixClient.verificationMethods,
      ...supportedVerificationMethods,
    };
  }

  /// Whether this client can start an in-room E2EE verification with [userId].
  bool canVerifyUser(String userId) {
    final mx = client.matrixClient;
    return mx.isLogged() &&
        mx.encryptionEnabled &&
        userId.isNotEmpty &&
        userId != mx.userID;
  }

  /// Starts an in-room E2EE verification (`m.key.verification.request`) with
  /// another Matrix user. Queries their device and cross-signing keys first
  /// when missing or outdated so SAS/QR and `user_signing` cross-signing have
  /// their master key available.
  Future<KeyVerification> startUserVerification(
    String userId, {
    bool? newDirectChatEnableEncryption,
  }) async {
    final mx = client.matrixClient;
    if (!mx.isLogged() || !mx.encryptionEnabled) {
      throw StateError('End-to-end encryption is not enabled for this session');
    }
    if (userId.isEmpty || userId == mx.userID) {
      throw ArgumentError.value(
        userId,
        'userId',
        'Expected another Matrix user ID',
      );
    }

    enableVerificationMethods();

    final existing = mx.userDeviceKeys[userId];
    if (existing == null || existing.outdated) {
      await mx.updateUserDeviceKeys(additionalUsers: {userId});
    }

    final userKeys = mx.userDeviceKeys[userId];
    if (userKeys == null) {
      throw StateError('Unable to fetch encryption keys for $userId');
    }

    return userKeys.startVerification(
      newDirectChatEnableEncryption: newDirectChatEnableEncryption,
    );
  }

  /// Validates a scanned, pasted or file-loaded QR payload and starts the
  /// `m.reciprocate.v1` step on [request].
  ///
  /// Throws [QrPayloadFormatException] for malformed payloads or a payload
  /// belonging to a different transaction without cancelling [request], so the
  /// user can correct their input. Cancels [request] with `m.key_mismatch`
  /// when the payload's public keys do not match the expected keys.
  Future<bool> submitScannedQrPayload(
    KeyVerification request,
    Uint8List rawBytes,
  ) =>
      submitQrPayload(request, rawBytes);

  /// Parses [text] (Base64, Base64URL, hex, or raw `MATRIX` string) and
  /// submits it to [submitScannedQrPayload].
  Future<bool> submitScannedQrText(KeyVerification request, String text) {
    final bytes = MatrixQrVerificationPayload.decodeInput(text);
    return submitScannedQrPayload(request, bytes);
  }

  /// Parses [fileBytes] (raw `MATRIX` binary or UTF-8 text file) and submits
  /// it to [submitScannedQrPayload].
  Future<bool> submitScannedQrFileBytes(
    KeyVerification request,
    Uint8List fileBytes,
  ) {
    final payload = MatrixQrVerificationPayload.parseFileBytes(fileBytes);
    return submitScannedQrPayload(request, payload.rawBytes);
  }

  /// Shared QR payload validator and reciprocation starter so UI without a
  /// component instance follows the exact same security rules.
  static Future<bool> submitQrPayload(
    KeyVerification request,
    Uint8List rawBytes,
  ) async {
    final payload = MatrixQrVerificationPayload.parseBytes(rawBytes);
    final validation = payload.validateForRequest(request);
    switch (validation) {
      case QrKeyValidationResult.transactionMismatch:
        throw const QrPayloadFormatException(
          QrPayloadParseError.transactionMismatch,
        );
      case QrKeyValidationResult.keyMismatch:
      case QrKeyValidationResult.unverifiedOwnMasterKey:
        await request.cancel('m.key_mismatch');
        return false;
      case QrKeyValidationResult.valid:
        await request.continueVerification(
          matrix.EventTypes.Reciprocate,
          qrDataRawBytes: payload.rawBytes,
        );
        return !request.canceled && request.state != KeyVerificationState.error;
    }
  }

  /// Rejects a QR scan confirmation when the other side does not show a
  /// matching verification screen, cancelling cleanly with [code] (defaults
  /// to `m.key_mismatch`).
  Future<void> rejectQrScanConfirmation(
    KeyVerification request, {
    String code = 'm.key_mismatch',
  }) async {
    if (!request.isDone) {
      await request.cancel(code);
    }
  }

  /// Cancels an active verification request cleanly (defaults to `m.user`).
  Future<void> cancelVerification(
    KeyVerification request, {
    String code = 'm.user',
  }) async {
    if (!request.isDone) {
      await request.cancel(code);
    }
  }

  /// [needsVerification], as of the last [check]: the prompt and the
  /// undecrypted messages' line follow it.
  final ValueNotifier<bool> needed = ValueNotifier(false);

  /// The notice in the Home screen's alerts while [needed].
  Alert? _alert;

  /// Set by a fresh login: the prompt opens once, as soon as this device's
  /// keys are known.
  bool _askOnce = false;

  final List<StreamSubscription> _subscriptions = [];

  /// The requests of the server's steps a dialog was opened for.
  final Expando<bool> _uiaShown = Expando();

  /// Opens the prompt once this device's keys are known, if it has to be
  /// verified. Called by a fresh login, before [postLoginInit].
  void askAfterLogin() => _askOnce = true;

  @override
  void postLoginInit() {
    Log.i("Registering key verification listeners");
    enableVerificationMethods();

    if (_subscriptions.isEmpty) {
      _subscriptions.add(
        client.matrixClient.onKeyVerificationRequest.stream.listen((event) {
          final context = navigator.currentContext;
          if (context == null) return;
          AdaptiveDialog.show(
            context,
            builder: (_) =>
                MatrixVerificationPage(request: event, component: this),
            title: labelAppVerificationRequest,
          );
        }),
      );

      _subscriptions.add(
        client.matrixClient.onUiaRequest.stream.listen((event) {
          // A request waits again after each refusal (a wrong password, an
          // approval not seen yet): its dialog is already open.
          final context = navigator.currentContext;
          if (context != null &&
              event.state == matrix.UiaRequestState.waitForUser &&
              _uiaShown[event] != true) {
            _uiaShown[event] = true;
            AdaptiveDialog.show(
              context,
              builder: (_) => MatrixUIARequest(event, client),
              title: labelAppAuthenticationRequest,
            );
          }
        }),
      );

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
      if (need) _askAfterLoginNavigation();
    }
  }

  /// Opens the prompt after the next frame. The login returns before the
  /// login page navigates ("Add account" pops itself, the first login gives
  /// way to the app): a prompt opened before that would be the route the
  /// pop closes, leaving the login page open.
  void _askAfterLoginNavigation() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      final context = navigator.currentContext;
      if (context == null || !needsVerification(client.matrixClient)) return;
      VerifyThisDevice.show(context, client);
    });
    binding.scheduleFrame();
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

  /// Refreshes device and cross-signing keys for [userId] after verification
  /// completes. For our own account this delegates to [refresh].
  Future<void> refreshUserKeys(String userId) async {
    final mx = client.matrixClient;
    if (userId == mx.userID) {
      await refresh();
      return;
    }
    try {
      mx.userDeviceKeys[userId]?.outdated = true;
      await mx.updateUserDeviceKeys(additionalUsers: {userId});
    } catch (error, stack) {
      Log.onError(
        error,
        stack,
        content: "Could not refresh verified user's keys",
      );
    }
  }
}
